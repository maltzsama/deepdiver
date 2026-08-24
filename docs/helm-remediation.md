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

## Pod/container security

The migration Job (pre-install/pre-upgrade hook) got the container
`securityContext` (`runAsNonRoot`, `allowPrivilegeEscalation: false`,
`drop: ALL`, seccomp `RuntimeDefault`) so it survives a PSA-restricted
namespace.

## Kubernetes access from the app

- `K8S_NAMESPACE` (via `fieldRef: metadata.namespace`) and `HELM_RELEASE`
  (`{{ .Release.Name }}`) are injected into web + worker + migration pods, so
  `TrinoSecretMaterializer` writes the credentials Secret into the right
  namespace/release instead of `default`/`lakedeepdiver`.
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
`get`/`update`/`patch` restricted to `<fullname>-trino-catalog-secrets` via
`resourceNames`, `create` kept in a separate unscoped rule, `list` dropped.

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

## Still open / verify under load

- **Cross-database race**: `start_execution_on_engine` updates the execution to
  `running` on the primary DB inside the supervisor lock, then enqueues on the
  queue DB (independent commit). An engine worker could consume the job before
  the primary commit, read `pending` and skip. Confirm under load.
- **CI does not build the image**: only the release workflow builds/pushes the
  Docker image, so a broken Dockerfile surfaces only at release time.
- **cache_store**: `:memory_store` with `replicaCount > 1` makes in-memory
  counters diverge between replicas (cosmetic).