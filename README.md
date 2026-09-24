# <img src="public/icon.svg" alt="" width="48"> DeepDiver

[![CI](https://github.com/maltzsama/deepdiver/actions/workflows/ci.yml/badge.svg)](https://github.com/maltzsama/deepdiver/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v0.12.4-blue.svg)](CHANGELOG.md) <!-- x-release-please-version -->
[![Ruby](https://img.shields.io/badge/ruby-4.0.6-red.svg)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-8.1-brightgreen.svg)](https://rubyonrails.org/)

Rails 8 control plane for Iceberg table maintenance (optimize, expire snapshots, orphan/rewrite)
with an ephemeral Trino engine on Kubernetes.

## Features

- Devise authentication with an `admin` role (RBAC on mutating routes).
- Catalog sync from Iceberg REST catalogs (Polaris and Nessie) driven by `CatalogSyncService` +
  `HealthEvaluator` health scoring.
- Maintenance dispatch by model `dispatchable` schedules via Fugit cron and Solid Queue
  recurring tasks.
- Ports/adapters Trino runtime: `FakeTrinoRuntime` in dev/test, `RealTrinoRuntime`
  (kubeclient scale up/down + Trino REST) with `TRINO_RUNTIME=real` in production.
- Configurable Trino engine topology: single-node or coordinator + separate workers,
  managed from the admin UI (Engine config screen).
- Freshness monitoring with SLA probes and Slack/email alerting.
- Pundit policies for admin/viewer/operator RBAC.

## Stack

- Rails 8.1 / Ruby 4.0, Propshaft + importmap, Hotwire.
- Solid Queue (no Redis) on PostgreSQL; production uses CloudNativePG with `DATABASE_URL`
  (app) and `DB_QUEUE_URL` (queue schema).
- `fugit` for cron parsing, `kubeclient` for the in-cluster Trino control.
- Trino 482 with baleia catalog-store plugin (ephemeral, app-managed).

## Setup

```bash
bin/setup                 # installs gems and DB (dev/test on sqlite3)
bin/dev                   # web server + Tailwind CSS watcher
bin/rails jobs            # Solid Queue workers + recurring tasks
bin/rails test            # test suite
```

`bin/dev` runs both the Rails server and the Tailwind watcher (`bin/rails
tailwindcss:watch`), so the compiled stylesheet stays in sync with
`app/assets/tailwind/application.css`. If you only run `bin/rails server`,
rebuild the CSS once with `bin/rails tailwindcss:build`.

Default seeded user: `admin@example.com` / `changeme!` (admin).

## Configuration

All production secrets come from the environment (Helm chart secrets). The table below
lists every environment variable the application reads.

### Database

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATABASE_URL` | Yes | — | PostgreSQL connection string for the app schema. |
| `DB_QUEUE_URL` | Yes | — | PostgreSQL connection string for the Solid Queue schema. |

### Rails core

| Variable | Required | Default | Description |
|---|---|---|---|
| `RAILS_MASTER_KEY` | Yes | — | Decrypts `credentials.yml.enc`. |
| `SECRET_KEY_BASE` | Yes | — | Session/cookie/signing secret. |
| `RAILS_ENV` | No | `development` | Runtime environment. |
| `RAILS_LOG_LEVEL` | No | `info` | Log verbosity (`debug`, `info`, `warn`, `error`). |
| `RAILS_MAX_THREADS` | No | `5` | Puma max threads per worker. |
| `RAILS_ASSUME_SSL` | No | `false` | Set `true` behind an SSL-terminating proxy. |
| `RAILS_FORCE_SSL` | No | `false` | Set `true` to redirect HTTP to HTTPS. |
| `RAILS_ALLOWED_HOSTS` | No | — | Comma-separated allowed Host headers (DNS rebinding guard). |
| `WEB_CONCURRENCY` | No | `0` | Puma worker processes (0 = single-threaded). |
| `SOLID_QUEUE_IN_PUMA` | No | `false` | Run Solid Queue inline inside Puma (no separate worker). |
| `PORT` | No | `3000` | HTTP listen port. |

### Encryption (Active Record)

| Variable | Required | Default | Description |
|---|---|---|---|
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Yes | — | Deterministic encryption key. |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Yes | — | Key derivation salt. |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Yes | — | Primary encryption key. |

### SSO / OIDC

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSO_ENABLED` | No | `false` | Enable OpenID Connect SSO login. |
| `OIDC_CLIENT_ID` | If SSO | — | OIDC client ID. |
| `OIDC_CLIENT_SECRET` | If SSO | — | OIDC client secret. |
| `OIDC_ISSUER` | If SSO | — | OIDC issuer URL (e.g. `https://keycloak.example.com/realms/app`). |
| `OIDC_REDIRECT_URI` | No | — | Callback URL override. |
| `OIDC_PROVIDER_LABEL` | No | `SSO` | Label shown on the login button. |
| `LOCAL_LOGIN_ENABLED` | No | `true` | Show the email/password login form (disable when SSO-only). |

### Trino engine — provisioning

| Variable | Required | Default | Description |
|---|---|---|---|
| `TRINO_URL` | Yes | — | Coordinator base URL (e.g. `http://trino-coordinator:8080`). |
| `TRINO_NAMESPACE` | No | Release ns | Kubernetes namespace of the Trino Deployments. |
| `TRINO_DEPLOYMENT` | No | `trino-coordinator` | Coordinator Deployment name. |
| `TRINO_WORKER_DEPLOYMENT` | No | `trino-worker` | Worker Deployment name. |
| `TRINO_RUNTIME` | No | `real` | `real` (kubeclient) or `fake` (dev/test). |
| `TRINO_PROVISIONER` | No | `chart` | `baleia` (catalog-store plugin), `chart` (Helm-style), or `fake`. |

> **Note:** `TRINO_PROVISIONER=chart` scales an *existing* Deployment (0 ↔ 1+ replicas). The consumer's own Helm chart or manifests must pre-create the coordinator (`trino-coordinator`) and, in cluster topology, worker (`trino-worker`) Deployments with `replicas: 0` before this application can start the engine. A missing Deployment produces a `ResourceNotFoundError` at boot.
| `TRINO_CLUSTER_NAME` | No | `default` | Baleia catalog-store cluster name. |

### Trino engine — tuning

| Variable | Required | Default | Description |
|---|---|---|---|
| `TRINO_READY_TIMEOUT_MINUTES` | No | `8` | Max wait for cluster readiness on start. |
| `TRINO_MAX_START_ATTEMPTS` | No | `2` | Start retries before marking engine failed. |
| `TRINO_START_POLL_SECONDS` | No | `5` | Polling interval during startup. |
| `TRINO_DRAIN_GRACE_MINUTES` | No | `5` | Grace period before draining idle engine. |
| `TRINO_DRAIN_POLL_SECONDS` | No | `10` | Polling interval during drain. |
| `TRINO_MAINT_MAX_SECONDS` | No | `21600` | Max seconds per maintenance step (6 h). |
| `TRINO_MAINT_POLL_SECONDS` | No | `1` | Polling interval for step completion. |
| `TRINO_QUERY_MAX_SECONDS` | No | `3600` | Max seconds per Trino query (1 h). |
| `TRINO_QUERY_POLL_SECONDS` | No | `1` | Polling interval for query completion. |
| `TRINO_HEARTBEAT_STALE_MINUTES` | No | `15` | Minutes before a running query is considered stale. |

### Kubernetes

| Variable | Required | Default | Description |
|---|---|---|---|
| `KUBE_API_URL` | No | In-cluster | Override the Kubernetes API endpoint. |
| `KUBE_TOKEN` | No | ServiceAccount | Bearer token for the Kubernetes API. |
| `KUBE_CA_FILE` | No | ServiceAccount | CA certificate file path. |

### Alerts

| Variable | Required | Default | Description |
|---|---|---|---|
| `SLACK_WEBHOOK_URL` | No | — | Default Slack webhook for alert delivery. |

### Other

| Variable | Required | Default | Description |
|---|---|---|---|
| `INTERNAL_CA_FILE` | No | — | Path to the internal root CA certificate. |
| `CEPH_ENDPOINT` | No | — | Ceph/S3 object-store endpoint. |

## Deployment (Helm)

The app ships as a Docker image consumed by the Helm chart under `infra/helm/deepdiver`
(on-prem, no Redis/Kamal). It deploys three workloads plus a migration hook:

- web — Puma (`bin/rails server`)
- `worker` — Solid Queue supervisor (`bin/jobs`, maintenance + recurring schedules)
- `worker-freshness` — its own Solid Queue process (freshness sweeps)
- `migrationJob` — a `pre-install`/`pre-upgrade` hook that runs `bin/rails db:migrate`
  before web/worker reach readiness

Deployment is not wired into CI; publish the image yourself and install the chart.

### Prerequisites

- A PostgreSQL database (two logical databases: the app + `..._queue` for Solid Queue).
- An object store / Iceberg catalog (Polaris/Nessie) reachable from the cluster.
- An ephemeral Trino engine: a Deployment (default name `trino-coordinator`) that the app
  scales 0<->1 through `apps/deployments` and `apps/deployments/scale` RBAC.
- The on-prem PKI root CA in a Secret (for HTTPS to catalog/Trino) if issued by a private CA.

### Build, render and install

```bash
# 1. Build and push the image once per release (tag is pinned, never "latest").
docker build -t registry.example.com/deepdiver:0.1.0 .
docker push registry.example.com/deepdiver:0.1.0

# 2. Render and validate without a cluster.
helm lint infra/helm/deepdiver
helm template deepdiver infra/helm/deepdiver \
  --values infra/helm/values/prod.yaml

# 3. Install or upgrade.
helm upgrade --install deepdiver infra/helm/deepdiver \
  --namespace deepdiver --create-namespace \
  --values infra/helm/values/prod.yaml \
  --set image.tag=0.1.0
```

### Required values

| Value | Purpose |
|---|---|
| `image.repository` / `image.tag` | Built image and pinned version. |
| `appSecrets.existingSecret` | Out-of-band Secret with `DATABASE_URL`, `DB_QUEUE_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`. |
| `internalCA.existingSecret` | Secret (key `ca.crt`) with the internal root CA; mounted and set as `SSL_CERT_FILE`. |
| `env.trinoUrl` | Base URL of the Trino coordinator (e.g. `http://trino-coordinator:8080`). |
| `env.trinoNamespace` | Namespace of the Trino Deployment to scale (defaults to the release namespace). |
| `env.trinoDeployment` | Deployment name (default `trino-coordinator`). |
| `worker.replicaCount`, `workerFreshness.replicaCount` | Workers; 1 each is the default. |

`infra/helm/values/prod.yaml` holds the reference production overrides.

### Secrets and the internal CA

The chart never renders credentials or certificates. `appSecrets.existingSecret` and
`internalCA.existingSecret` are created by ArgoCD, SealedSecrets, or any external controller.
Set `appSecrets.create=true` + `appSecrets.data` only for throwaway local experiments.

### Catalog credential runbook

Catalog secrets live in `catalog_credentials.secret`, encrypted at rest with Active
Record Encryption (non-deterministic). Derived OAuth tokens are never persisted.

**Rotating a catalog credential:** edit the catalog in the UI and type the new secret
into the password field. A blank field keeps the stored value; there is no way to
accidentally clear it. After saving, the next sync picks up the new secret (the token
cache key changes with the credential row).

**After any suspected exposure:** rotate the credential on the provider first, then
update it here. Encryption protects storage/backups going forward - it cannot un-leak
a token already copied elsewhere. Old application logs from before the encrypted-
credential migration may contain plaintext tokens; treat them as burned.

**If the encryption keys are lost**, every stored credential becomes unreadable - no
recovery exists by design. Re-enter each catalog's credential through the UI after
provisioning a new key set (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
`_DETERMINISTIC_KEY`, `_KEY_DERIVATION_SALT`). Keep the three keys only as
Kubernetes Secrets; losing them is equivalent to losing the credentials themselves.

**Nessie refs:** a Nessie catalog reads its server default branch unless
`nessie_ref` is set on the catalog record. The ref IS the Iceberg REST prefix
(Nessie answers `/iceberg/v1/config` with `prefix = <default ref>`); the app
pins it per catalog and Trino must read the SAME ref. Trino's REST connector
has no static branch property - queries only pin one via
`FOR VERSION AS OF`. Keep app `nessie_ref`, Trino's Nessie configuration and
any scheduled queries on the same branch, or health numbers describe one
table while optimize rewrites another.

**Dremio Open Catalog note:** the app authenticates via RFC 8693 token exchange
against the external token server (`:9047/oauth/token`), storing only the PAT.
The Trino side of that catalog needs its own auth configuration in the
`trino_catalog_registry` properties - if the Baleia plugin does not support token
exchange, maintenance runs against Dremio tables are blocked even though sync works.

### After install

```bash
helm status deepdiver -n deepdiver
kubectl -n deepdiver get pods    # web, worker, worker-freshness all Running
kubectl -n deepdiver logs job/deepdiver-migrate   # migration hook output
```

Register a catalog in the UI (admin), then **Sync now** on the Tables screen to import
namespaces/tables. Clicking **Run** on a table scales Trino up, runs the maintenance chain,
and scales it back down. The Activity screen shows the engine lifecycle, the live pipeline,
and a **Hard reset** button to tear a frozen engine down.

Full parameter reference, RBAC details and the internal-CA trust model are in
`infra/helm/deepdiver/README.md`.

## Generating docs

```bash
bundle exec rake docs:build     # generate RDoc + inject counter.dev tracking
bundle exec rake docs:inject_counter  # re-inject tracking after manual rdoc regen
```

## Security

The `trino_catalog_registry` table contains Trino connector credentials in
plaintext (required by the Baleia plugin). See [docs/security.md](docs/security.md)
for mitigations, database role separation, and backup handling.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## License

DeepDiver is licensed under the [Apache License 2.0](LICENSE).
