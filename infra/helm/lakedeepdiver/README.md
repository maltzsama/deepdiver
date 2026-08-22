# lakedeepdiver

LakeDeepDiver — Iceberg maintenance control plane (Rails 8 + Solid Queue).

## Installation

```bash
helm repo add lakedeepdiver https://maltzsama.github.io/lakedeepdiver
helm repo update
helm install lakedeepdiver lakedeepdiver/lakedeepdiver \
  --set postgresql.existingSecret=lakedeepdiver-db \
  --set activeRecordEncryption.existingSecret=lakedeepdiver-encryption
```

## Prerequisites

- PostgreSQL accessible from the cluster
- Secret with Active Record Encryption keys (see below)
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
| `image.tag` | `0.1.0` | Docker image tag |
| `postgresql.existingSecret` | `""` | **Required.** Secret with `url` key |
| `activeRecordEncryption.existingSecret` | `""` | **Required.** Secret with `primary_key`, `deterministic_key`, `key_derivation_salt` |
| `appSecrets.existingSecret` | `""` | Secret with `DATABASE_URL`, `DB_QUEUE_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE` |
| `internalCA.enabled` | `false` | Mount an internal CA certificate |
| `internalCA.existingSecret` | `""` | Secret containing the CA cert |
| `trino.provisioner` | `fake` | Trino provisioner: `chart`, `baleia`, or `fake` |
| `oidc.issuer` | `""` | OIDC issuer URL (enables SSO) |
| `env.trinoUrl` | `""` | Trino coordinator URL |
| `env.logLevel` | `info` | Rails log level |
| `worker.enabled` | `true` | Deploy Solid Queue worker |
| `workerFreshness.enabled` | `true` | Deploy freshness worker |
| `workerEngine.enabled` | `true` | Deploy engine lifecycle worker |
| `migrationJob.enabled` | `true` | Run DB migrations as Helm hook |
| `resources` | `{}` | Pod resource requests/limits |
| `securityContext` | see values.yaml | Pod security context |

## License

Apache-2.0. See [LICENSE](../../../LICENSE).
