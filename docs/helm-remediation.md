# Helm installation remediation

Notes on the fixes that make the Helm chart usable in production. Each entry
maps to a finding from the installation review; the corresponding PR is
listed where relevant.

## Login after install (was: impossible)

The app seeds an admin only from `BOOTSTRAP_ADMIN_EMAIL` + `BOOTSTRAP_ADMIN_PASSWORD`
(`db/seeds.rb`), but the chart never emitted them — so after `helm install`
there was no way to sign in (the demo admin is gated behind
`development? || SEED_DEMO`). The chart now has:

```yaml
admin:
  bootstrap:
    email: ""
    password: ""
```

Both vars are emitted only when **both** are set (`{{- if and ... }}`). Setting
just the email would make the migration Job fail (`ENV.fetch` KeyError in the
seed).

## Chart values that were dead

- `trino.provisioner` was never emitted; the app silently fell back to
  `"chart"`. It is now emitted, and the chart default is `chart` (a plain
  install provisions the ephemeral Deployment instead of a stub).
- `oidc.*` were never emitted; SSO was documented but impossible. `SSO_ENABLED`
  + `OIDC_*` are now emitted when `oidc.issuer` is set.
- `env.host` was emitted as `HOST`, which the app does not read (it reads
  `APP_HOST` for mailer links). Now emitted as `APP_HOST`.
- `env.jobConcurrency` was emitted as `JOB_CONCURRENCY`, which the app does not
  read (concurrency comes from `config/queue-*.yml`). Dropped from the ConfigMap.
- `postgresql.existingSecret` / `urlKey` are still not consumed by any template;
  the app reads `DATABASE_URL` from `appSecrets.existingSecret`.

## TRINO_URL / TRINO_DEPLOYMENT

`TRINO_URL` was guarded by `{{- if }}` while `TRINO_DEPLOYMENT` was always
emitted (even as `""`), so a blank deployment made `K8sClientFactory` target an
empty name. Both are now guarded by `{{- if }}` — absent when empty.

Superseded in round 2: guarding alone still let the chart install into a state
that raises `KeyError` on the first "Run". Both now carry conventional defaults
and are enforced non-empty by `values.schema.json`.

## Pod/container security

The migration Job (pre-install/pre-upgrade hook) got the container
`securityContext` (`runAsNonRoot`, `allowPrivilegeEscalation: false`,
`drop: ALL`, seccomp `RuntimeDefault`) so it survives a PSA-restricted
namespace.

## Kubernetes access from the app

- `K8S_NAMESPACE` (via `fieldRef: metadata.namespace`) and `HELM_RELEASE`
  (`{{ .Release.Name }}`) are injected into web + worker + migration pods, so
  `TrinoSecretMaterializer` no longer falls back to `default`/`lakedeepdiver`.
  Round 2 made the Secret's namespace prefer `TRINO_NAMESPACE` and its name come
  from the chart.
- `TrinoSecretMaterializer` now authenticates to the Kubernetes API with the
  ServiceAccount bearer token and CA (reusing `K8sClientFactory`), instead of
  calling anonymously (401) with a nil CA.

## SSL trust

`SSL_CERT_FILE` used to point only at the internal CA, which **replaces** the
system trust bundle and breaks HTTPS to public endpoints (e.g. Slack webhooks).
It is no longer set. `INTERNAL_CA_FILE` is consumed by `HttpTransport` as an
explicit `ca_file` for catalog/Trino TLS, so the internal CA still works
without poisoning the bundle.

## Engine heartbeat / orphan reaping

`TrinoDemand.reap_orphans!` compared `last_heartbeat_at < stale`, which
excluded NULL heartbeats. A running execution whose worker died before the
first Trino poll stayed `running` forever (demand never drained, table lock
never released). The reaping query now uses
`COALESCE(last_heartbeat_at, started_at)`, and the `pending -> running`
transition stamps `last_heartbeat_at`.

## RBAC

The Role granted `get/list/create/update/patch` on **all** secrets in the
release namespace (including the app's own Secret). It is now scoped:
`get`/`update`/`patch` restricted to the materialized Secret via
`resourceNames`, `create` kept in a separate unscoped rule, `list` dropped.

Superseded in round 2: the authorized name did not match the one the app wrote.
The name now comes from a single helper and is handed to the app as
`TRINO_CATALOG_SECRET_NAME`.

## Maintenance step config

`retention_threshold`, `file_size_threshold` and `snapshot_ids` are
interpolated into the `ALTER TABLE ... EXECUTE` statement. They are now
validated at the model: thresholds must be a magnitude-plus-unit
(`7d`, `128MB`, `1.5GB`) and `snapshot_ids` a comma-separated list of
integers. The `where` clause remains free-form by design; plan edits are
admin-only via Pundit.

## Release pipeline

- The `chart` job uploaded `.cr-index` (the gh-pages branch checked out by
  `helm/chart-releaser-action`), which contains a `.git` dir that
  `upload-artifact@v4` refuses to upload. A clean `chart-index` dir (only
  `index.yaml` + `artifacthub-repo.yml`) is uploaded instead.
- The `pages` job now downloads only the `chart` and `docs` artifacts by name,
  avoiding the internal `*.dockerbuild` artifact from `docker/build-push-action`
  that intermittently failed the download.

## Round 2: regressions the first round introduced

### Worker pods lost their securityContext

`migration-job.yaml` was fixed by applying `.Values.securityContext`, but the
three worker Deployments still read their own `worker*.securityContext`, which
defaults to `{}` — so `{{- with }}` skipped it and they rendered with no
security context at all. Under Pod Security Admission `restricted` the
Deployments are created but every pod is rejected, so `helm status` looks
healthy while no job, schedule or freshness sweep ever runs. They now fall back
to the top-level context: `default .Values.securityContext .Values.worker.securityContext`.

### The RBAC scope authorized a name nothing wrote

The Role restricted `get`/`update`/`patch` to
`<fullname>-trino-catalog-secrets`, but `TrinoSecretMaterializer` computed
`<HELM_RELEASE>-trino-catalog-secrets` — and `fullname` is
`<release>-<chart>`, so the two never matched. `get_secret` returned 403,
which is `Kubeclient::HttpError` and not `ResourceNotFoundError`
(`kubeclient/common.rb` only maps 404 to the latter), so the `rescue` that
would have created the Secret never fired and the outer rescue swallowed it:
credentials silently never materialized.

The name is now computed once, in `lakedeepdiver.trinoSecretName`, and used by
both the Role's `resourceNames` and the `TRINO_CATALOG_SECRET_NAME` env var the
app reads. The app no longer derives it. The swallowing rescue logs at `error`
with the namespace, name and HTTP status, and records an ErrorEvent.

### Secrets were rendered into a ConfigMap

`OIDC_CLIENT_SECRET` and `BOOTSTRAP_ADMIN_PASSWORD` were emitted into the
ConfigMap — readable by anyone with `get configmap` in the namespace and kept
in the Helm release. They moved to a `<fullname>-chart-env` Secret, mounted by
every workload through the shared `lakedeepdiver.envFrom` helper.

Every pod, not just web: `config/initializers/devise.rb` runs `ENV.fetch` on
the OIDC vars in every process, so a worker without `OIDC_CLIENT_SECRET` while
`SSO_ENABLED=true` is a boot-time KeyError.

### prod.yaml pinned a stale image tag

`infra/helm/values/prod.yaml` was on `0.1.7` while the chart was `0.2.1`,
because the `x-release-please-version` marker lived only in `values.yaml` and
`Chart.yaml`. Installing with prod.yaml therefore shipped an image predating
`SKIP_DB_PREPARE` (0.1.8), reintroducing the web-pod migration race the chart
believed it had fixed — and dropping the step-config validation and the
cross-database retry with it. The file is now a release-please extra-file and
carries the marker, as does the `artifacthub.io/images` annotation.

### The credentials Secret went to the wrong namespace

The cross-namespace Role exists so the app can materialize the Secret where
Trino runs, but the app wrote to `K8S_NAMESPACE` (its own pod's namespace). It
now prefers `TRINO_NAMESPACE` and falls back to `K8S_NAMESPACE`.

## Round 2: fixes that had not gone far enough

### The cross-database retry leaked a different way

`retry_pending` gave up after `MAX_RETRIES` and left the execution `pending`
forever. `pending` counts as demand, `reap_orphans!` only looked at `running`,
and `EngineWatchdogJob` only watches the engine row — so the engine never
drained and `run_plan`'s already-queued guard blocked that table permanently.

Two changes: the job now fails the execution explicitly through
`ExecutionFailureHandler` and signals `demand_finished!`; and
`TrinoDemand.reap_orphans!` also reaps executions left `pending` past
`TRINO_PENDING_STALE_MINUTES` (default 45, comfortably above
`READY_TIMEOUT * MAX_START_ATTEMPTS`), covering the case where the dispatch
never arrived at all.

`ExecutionHistory#retry_count` is now cleared once the dispatch is visible;
otherwise a healthy execution rendered as "retrying" for the rest of its chain.

### Blank TRINO_URL / TRINO_DEPLOYMENT installed happily

Guarding both with `{{- if }}` stopped the empty-string bug but produced a
chart that installs into a state that raises `KeyError` on the first "Run",
with nothing to catch it — `values.schema.json` had no `env` block at all.
They now default to the conventional in-cluster names and are enforced
non-empty by the schema, which also requires the OIDC quartet together and
the bootstrap admin email/password as a pair.

### Kubeclient errors bypassed the engine retry

`ChartTrinoProvisioner` let `Kubeclient` errors escape, but
`SuperviseEngineStartJob` only rescues `TrinoProvisioner::Error` and
`Timeout::Error` and `ApplicationJob` has no generic retry — so a missing
Deployment or a 403 killed the job, skipped `MAX_START_ATTEMPTS`, and left the
engine in `starting` until the watchdog failed it minutes later. They are now
wrapped as `TrinoProvisioner::Error` with the addressed `namespace/deployment`
in the message. A worker Deployment absent on `destroy!` is tolerated, since
single topology legitimately has none.

`env.trinoWorkerDeployment` is now a chart value; the default engine topology
is `cluster`, so the worker Deployment name was previously unreachable from
the chart.

## Still open / verify under load

- **Cross-database race**: handled by a bounded retry plus an explicit failure
  and the pending reaper above, but the 5s x 3 retry window is a guess. Confirm
  under load that a primary commit is always visible within it.
- **Unscoped Secret `create`**: `resourceNames` is ignored for `create`, so the
  app can create (not overwrite) an arbitrary Secret in the release and Trino
  namespaces. Closing this needs an admission policy (Kyverno/Gatekeeper), not
  RBAC - there is no RBAC expression for "create only this name".
- **cache_store**: `:memory_store` is per-process. For the catalog OAuth token
  cache that is correct, just not shared - each pod performs its own token
  exchange. For `failed_execution_count` (30s TTL) it means replicas can show
  slightly different numbers. Left as is deliberately: a shared cache would add
  a dependency for no correctness gain.

## Round 3: application-level findings

Found while reviewing the code the earlier rounds had not covered (catalog sync,
freshness, retention, authorization).

### A failed sync deactivated tables that still exist

`CatalogSyncService` rescues per table and per namespace, so a table whose sync
raised never reached `seen` - and `deactivate_unseen` then marked it "dropped
from the catalog". A namespace that failed to list took all of its tables with
it, and with every namespace failing `seen` was empty, where
`where.not(id: [])` renders as `1=1` and deactivated the entire catalog.

Deactivation is a real signal - it hides the table from the tables screen, from
freshness sweeps (which filter on `active`) and from maintenance dispatch - so a
transient catalog error silenced monitoring until the next successful sync, six
hours by default, with only a warn log.

It is now restricted to namespaces that synced with no errors at all.

### Retention deleted open errors that were still happening

`DataRetentionJob` pruned `ErrorEvent` by `created_at`, but `ErrorEvent.record`
dedupes by message: a recurring failure keeps its original `created_at` and only
bumps `last_seen_at`. An open error first seen 100 days ago and last seen an
hour ago was deleted by the nightly job. The schema's `[status, last_seen_at]`
index already pointed at the right column. Pruning is per-model now, with
`error_events` keyed on `last_seen_at`.

### The OAuth token's real expiry was discarded

`CatalogTokenProvider` wrapped `request_token` in `Rails.cache.fetch(...,
expires_in: 5.minutes)`. `fetch` writes the block's result itself, with the TTL
given to `fetch`, so the `expires_in` the provider returned was always thrown
away and a token valid for less than five minutes was served after it expired.
It self-healed through the retry-once on 401 in `CatalogClient#get`, so the cost
was a wasted round-trip rather than a failed sync. An explicit read/write pair
now honours the response's `expires_in`, keeping the conservative TTL only as
the fallback for providers that omit it.

### Freshness probes left queries running on the coordinator

`TrinoClient#query_scalar` returned as soon as it had enough rows, abandoning an
outstanding `nextUri`. Trino keeps such a query alive until its client timeout,
so `ChartTrinoProvisioner#idle?` reported the engine busy and every sweep held
it up for the whole drain grace period, logging "Drain grace period exhausted
with queries still active" with no real query behind it. The client now DELETEs
the outstanding `nextUri`, best effort.

### The engine state machine's compare-and-set did not compare

`TrinoEngineSupervisor.transition!` raised a "CAS lost" error that was
unreachable: its UPDATE matched on `id` alone, so it always affected one row.
The row lock in the callers was carrying the entire guarantee. The `generation`
predicate is now part of the UPDATE, which also makes a transition from a stale
record - the watchdog re-reads state outside the lock - fail loudly instead of
overwriting a concurrent transition.

### A forgotten `authorize` was indistinguishable from an intentional one

Pundit's `verify_authorized` was not enabled, so an action without `authorize`
simply ran for any signed-in user. An audit of all sixteen controllers found no
actual hole: the two actions without `authorize` (`ProfilesController`,
`ThemeController#toggle`) operate only on `current_user`, take no id parameter,
and exclude `role`/`status` from strong params. `verify_authorized` is now on
globally, with those two opting out explicitly so the decision is visible.

`verify_policy_scoped` is deliberately not enabled: index actions here authorize
the class rather than scoping a relation.

### Smaller

- `TrinoRestClient` reported `rows` from the final Trino page only. Trino
  streams rows on intermediate pages and the last one usually carries just
  columns, so the metric was ~0 regardless of the statement. It is counted
  across pages now, matching what `TrinoClient#poll` already did.
- `DataRetentionJob`'s Solid Queue retention duplicated its default instead of
  reading `DEFAULT_RETENTION`, leaving that constant entry dead. It is derived
  now, with the key renamed so the env override stays
  `SOLID_QUEUE_RETENTION_DAYS`.
- Every GitHub Action is on a current major. The third-party bumps held back
  last round (release-please v4 to v5, setup-helm v4 to v5, build-push-action v6
  to v7, login-action v3 to v4) turned out to be Node 24 runtime and ESM changes
  only; release-please's engine moved 17.3 to 17.6 as a fix, not a breaking
  change, and build-push-action v7 drops two deprecated env vars this repo does
  not set.

### Checked and found correct

Recorded so they are not re-investigated: `FreshnessProbe` quotes both
identifiers and literals, and `partition_lookback` is validated positive with a
DB default; `CatalogClient#get` retries exactly once on 401, because Ruby runs
`ensure` after `retry` rather than before, so there is no loop; suspension is
enforced per request by Devise's activatable hook through
`active_for_authentication?`, including OIDC sessions; and `delete_all` does
honour `limit`, via a subquery on the primary key.

## Observability: Prometheus metrics and structured logging

The chart does not create the `PodMonitor` (or the log collector): those are
owned by the cluster/platform team, out of this repo. What the chart does is
expose a scrapeable `/metrics` endpoint and structured JSON logs to STDOUT.

### Metrics

The web pod serves Prometheus metrics at `GET <metrics.path>` (default
`/metrics`) on port 80 — the same listener that serves the app, so there is no
extra port to open. The endpoint is a bare `ActionController::Metal`, open (no
auth) because the in-cluster `PodMonitor` cannot authenticate.

Application metrics are always on and derived from the database at scrape time
(`PrometheusMetrics.refresh!`), because only the web pod is scraped and any
counter a worker incremented in-process would be invisible:

- `lakedeepdiver_execution_status{status}` — maintenance executions by status.
- `lakedeepdiver_trino_engine_status{status}` — 1/0 per lifecycle state.
- `lakedeepdiver_error_events{status}` — error events by status.
- `lakedeepdiver_solid_queue_jobs{queue_name,state}` — jobs ready/running/
  blocked/scheduled/failed, per queue.

Service metrics (`lakedeepdiver_http_requests_total`, `http_request_duration`,
`sql_queries_total`, `sql_query_duration`, `process_cpu`, `process_resident_memory`)
are opt-in via `metrics.serviceMetrics: true`.

A `PodMonitor` for it looks like:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: lakedeepdiver
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: lakedeepdiver
      app.kubernetes.io/component: web
  podMetricsEndpoints:
    - port: http          # or 80
      path: /metrics
```

The pod also carries `prometheus.io/scrape`/`port`/`path` annotations for
clusters still using annotation-based discovery.

### Logging

Structured JSON logging is provided by `semantic_logger` +
`rails_semantic_logger`, replacing the previous `TaggedLogging` STDOUT logger.
`config/environments/production.rb` declares a single appender — JSON to
`$stdout` — so the platform's log collector (Promtail/Alloy → Loki, or Fluent
Bit → Logstash) parses every field. `logging.format: text` switches back to
human-readable lines via `LOG_FORMAT`. Because the appender is declared in the
Rails environment config, web, all three workers and the migration Job emit the
same shape.
