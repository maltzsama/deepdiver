# LakeDeepDiver

[![CI](https://github.com/maltzsama/lakedeepdiver/actions/workflows/ci.yml/badge.svg)](https://github.com/maltzsama/lakedeepdiver/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

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

## Stack

- Rails 8.1 / Ruby 4.0, Propshaft + importmap, Hotwire.
- Solid Queue (no Redis) on PostgreSQL; production uses CloudNativePG with `DATABASE_URL`
  (app) and `DB_QUEUE_URL` (queue schema).
- `fugit` for cron parsing, `kubeclient` for the in-cluster Trino control.

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

All production secrets come from the environment (Helm chart secrets):

- `DATABASE_URL`, `DB_QUEUE_URL` — PostgreSQL endpoints.
- `RAILS_MASTER_KEY` — Rails credentials.
- `TRINO_RUNTIME=real`, `TRINO_URL`, `TRINO_NAMESPACE`, `TRINO_DEPLOYMENT` — the
  ephemeral Trino engine to scale.
- `JOB_CONCURRENCY` — Solid Queue worker processes.

## Deployment (Helm)

The app ships as a Docker image consumed by the Helm chart under `infra/helm/lakedeepdiver`
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
  scales 0↔1 through `apps/deployments` and `apps/deployments/scale` RBAC.
- The on-prem PKI root CA in a Secret (for HTTPS to catalog/Trino) if issued by a private CA.

### Build, render and install

```bash
# 1. Build and push the image once per release (tag is pinned, never "latest").
docker build -t registry.example.com/lakedeepdiver:0.1.0 . <!-- x-release-please-version -->
docker push registry.example.com/lakedeepdiver:0.1.0 <!-- x-release-please-version -->

# 2. Render and validate without a cluster.
helm lint infra/helm/lakedeepdiver
helm template lakedeepdiver infra/helm/lakedeepdiver \
  --values infra/helm/values/prod.yaml

# 3. Install or upgrade.
helm upgrade --install lakedeepdiver infra/helm/lakedeepdiver \
  --namespace lakedeepdiver --create-namespace \
  --values infra/helm/values/prod.yaml \
  --set image.tag=0.1.0 <!-- x-release-please-version -->
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

### After install

```bash
helm status lakedeepdiver -n lakedeepdiver
kubectl -n lakedeepdiver get pods    # web, worker, worker-freshness all Running
kubectl -n lakedeepdiver logs job/lakedeepdiver-migrate   # migration hook output
```

Register a catalog in the UI (admin), then **Sync now** on the Tables screen to import
namespaces/tables. Clicking **Run** on a table scales Trino up, runs the maintenance chain,
and scales it back down. The Activity screen shows the engine lifecycle, the live pipeline,
and a **Hard reset** button to tear a frozen engine down.

Full parameter reference, RBAC details and the internal-CA trust model are in
`infra/helm/lakedeepdiver/README.md`.

## License

LakeDeepDiver is licensed under the [Apache License 2.0](LICENSE).