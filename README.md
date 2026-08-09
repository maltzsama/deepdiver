# LakeDeepDiver

Rails 8 control plane for Iceberg table maintenance (optimize, expire snapshots, orphan/rewrite)
with an ephemeral Trino engine on Kubernetes.

## Features

- Devise authentication with an `admin` role (RBAC on mutating routes).
- Catalog sync from Iceberg REST catalogs (Polaris and Nessie) driven by `CatalogSyncService` +
  `HEdlthEvaluator` health scoring.
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
bin/rails server
bin/rails jobs            # Solid Queue workers + recurring tasks
bin/rails test            # test suite
```

Default seeded user: `admin@example.com` / `changeme!` (admin).

## Configuration

All production secrets come from the environment (Helm chart secrets):

- `DATABASE_URL`, `DB_QUEUE_URL` — PostgreSQL endpoints.
- `RAILS_MASTER_KEY` — Rails credentials.
- `TRINO_RUNTIME=real`, `TRINO_URL`, `TRINO_NAMESPACE`, `TRINO_DEPLOYMENT` — the
  ephemeral Trino engine to scale.
- `JOB_CONCURRENCY` — Solid Queue worker processes.

## Deployment (Helm)

The app ships as a Docker image consumed by the Helm chart under `infra/helm/` (on-prem, no
Redis/Kamal). Deployment is not wired into CI.

```bash
docker build -t registry.example.com/lakedeepdiver:0.1.0 .
docker push registry.example.com/lakedeepdiver:0.1.0

helm upgrade --install lakedeepdiver infra/helm/lakedeepdiver \
  --namespace lakedeepdiver --create-namespace \
  --values infra/helm/values/prod.yaml
```

Charts never store secrets or certificates; `infra/helm/lakedeepdiver/README.md` documents
parameters, RBAC and the internal CA trust.