# lakedeepdiver

LakeDeepDiver — Iceberg maintenance control plane (Rails 8 + Solid Queue).

## Installation

```bash
helm repo add lakedeepdiver https://maltzsama.github.io/lakedeepdiver
helm repo update
helm install lakedeepdiver lakedeepdiver/lakedeepdiver \
  --set appSecrets.existingSecret=lakedeepdiver-secrets \
  --set activeRecordEncryption.existingSecret=lakedeepdiver-encryption \
  --set env.trinoUrl=http://trino-coordinator:8080 \
  --set env.trinoDeployment=trino-coordinator \
  --set admin.bootstrap.email=admin@example.com \
  --set admin.bootstrap.password='<choose-one>'
```

Without `admin.bootstrap.*` there is no way to sign in after the install: the
demo admin only exists in development or under `SEED_DEMO`.

## Prerequisites

- PostgreSQL accessible from the cluster
- Secret with Active Record Encryption keys (see below)
- The Trino coordinator Deployment named by `env.trinoDeployment`, and — when
  the engine topology is `cluster` (the default) — the worker Deployment named
  by `env.trinoWorkerDeployment`. A `cluster` topology pointing at a Deployment
  that does not exist fails the engine start; switch the topology to `single`
  on the Engine config screen if you run a single-node engine.
- OIDC provider (optional, for SSO)

## Generating encryption keys

```bash
bin/rails db:encryption:init
kubectl create secret generic lakedeepdiver-encryption \
  --from-literal=primary_key=... \
  --from-literal=deterministic_key=... \
  --from-literal=key_derivation_salt=...
```

> **Losing these keys makes all catalog credentials unrecoverable.**

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `lakedeepdiver` | Docker image repository |
| `image.tag` | `0.2.1` | Docker image tag |
| `activeRecordEncryption.existingSecret` | `""` | **Required.** Secret with `primary_key`, `deterministic_key`, `key_derivation_salt` |
| `appSecrets.existingSecret` | `""` | Secret with `DATABASE_URL`, `DB_QUEUE_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE` |
| `postgresql.existingSecret` | `""` | Not consumed by any template; the app reads `DATABASE_URL` from `appSecrets` |
| `internalCA.enabled` | `false` | Mount an internal CA certificate |
| `internalCA.existingSecret` | `""` | Secret containing the CA cert |
| `trino.provisioner` | `chart` | Trino provisioner: `chart`, `baleia`, or `fake` |
| `oidc.issuer` | `""` | OIDC issuer URL (enables SSO). Setting it requires `clientId`, `clientSecret` and `redirectUri` too |
| `admin.bootstrap.email` / `.password` | `""` | Seeds an admin on first install. Both or neither; the password is rendered into a Secret, not the ConfigMap |
| `env.trinoUrl` | `http://trino-coordinator:8080` | **Must be non-empty.** Read with a bare `ENV.fetch` |
| `env.trinoDeployment` | `trino-coordinator` | **Must be non-empty.** Coordinator Deployment to scale |
| `env.trinoWorkerDeployment` | `""` | Worker Deployment; needed when the engine topology is `cluster` (the default) |
| `env.trinoNamespace` | `""` | Namespace of the Trino Deployments; empty means the release namespace |
| `env.allowedHosts` | `[]` | `RAILS_ALLOWED_HOSTS` entries; include the ingress host |
| `env.logLevel` | `info` | Rails log level |
| `worker.enabled` | `true` | Deploy Solid Queue worker |
| `workerFreshness.enabled` | `true` | Deploy freshness worker |
| `workerEngine.enabled` | `true` | Deploy engine lifecycle worker |
| `migrationJob.enabled` | `true` | Run DB migrations as Helm hook |
| `resources` | `{}` | Pod resource requests/limits |
| `securityContext` | see values.yaml | Container security context, applied to every workload. The per-worker `worker*.securityContext` keys override it and inherit this when empty |
| `podSecurityContext` | `{}` | Pod-level security context |

`env.trinoUrl` and `env.trinoDeployment` are enforced non-empty by
`values.schema.json`: the app reads both with a bare `ENV.fetch`, so a blank
value is a `KeyError` on the first engine start rather than at install time.

## License

Apache-2.0. See [LICENSE](../../../LICENSE).
