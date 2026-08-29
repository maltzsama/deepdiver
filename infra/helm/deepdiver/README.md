<img src="https://raw.githubusercontent.com/maltzsama/deepdiver/main/public/icon.svg" width="72" height="72" alt="DeepDiver">

# deepdiver

DeepDiver — Iceberg maintenance control plane (Rails 8 + Solid Queue).

## Installation

```bash
helm repo add deepdiver https://maltzsama.github.io/deepdiver
helm repo update
helm install deepdiver deepdiver/deepdiver \
  --set appSecrets.existingSecret=deepdiver-secrets \
  --set activeRecordEncryption.existingSecret=deepdiver-encryption \
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
kubectl create secret generic deepdiver-encryption \
  --from-literal=primary_key=... \
  --from-literal=deterministic_key=... \
  --from-literal=key_derivation_salt=...
```

> **Losing these keys makes all catalog credentials unrecoverable.**

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `ghcr.io/maltzsama/deepdiver` | Docker image repository |
| `image.tag` | see values.yaml | Docker image tag |
| `imagePullSecrets` | `[]` | e.g. `[{name: my-registry-creds}]`, for a private registry mirror |
| `activeRecordEncryption.existingSecret` | `""` | **Required.** Secret with `primary_key`, `deterministic_key`, `key_derivation_salt` |
| `appSecrets.existingSecret` | `""` | Secret with `DATABASE_URL`, `DB_QUEUE_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE` |
| `internalCA.enabled` | `false` | Mount an internal CA certificate |
| `internalCA.existingSecret` | `""` | Secret containing the CA cert |
| `internalCA.mountFile` | `/etc/deepdiver/certs/internal-ca.crt` | Where the CA cert is mounted. Keep this outside `/etc/ssl/certs`: the mount replaces the whole containing directory, and that path is the system CA bundle |
| `trino.provisioner` | `chart` | Trino provisioner: `chart`, `baleia`, or `fake`. RBAC to patch/scale the Trino Deployment is granted for `chart`/`baleia`; the Secret rules used by catalog sync are granted regardless |
| `oidc.issuer` | `""` | OIDC issuer URL (enables SSO). Setting it requires `clientId`, `clientSecret` and `redirectUri` too |
| `admin.bootstrap.email` / `.password` | `""` | Seeds an admin on first install. Both or neither; the password is rendered into a Secret, not the ConfigMap |
| `env.trinoUrl` | `http://trino-coordinator:8080` | **Must be non-empty.** Read with a bare `ENV.fetch` |
| `env.trinoDeployment` | `trino-coordinator` | **Must be non-empty.** Coordinator Deployment to scale |
| `env.trinoWorkerDeployment` | `""` | Worker Deployment; needed when the engine topology is `cluster` (the default) |
| `env.trinoNamespace` | `""` | Namespace of the Trino Deployments; empty means the release namespace |
| `env.allowedHosts` | `[]` | `RAILS_ALLOWED_HOSTS` entries; include the ingress host |
| `env.logLevel` | `info` | Rails log level |
| `worker.enabled` | `true` | Deploy the Solid Queue worker. `false` omits the Deployment entirely |
| `workerFreshness.enabled` | `true` | Deploy the freshness worker. `false` omits the Deployment entirely |
| `workerEngine.enabled` | `true` | Deploy the engine lifecycle worker. `false` omits the Deployment entirely |
| `migrationJob.enabled` | `true` | Run DB migrations as a Helm hook |
| `resources` | see values.yaml | web pod resource requests/limits |
| `securityContext` | see values.yaml | Container security context, applied to every workload. The per-worker `worker*.securityContext` keys override it and inherit this when empty |
| `podSecurityContext` | `{}` | Pod-level security context |
| `automountServiceAccountToken` | `true` | Applied to web and all three workers (they call the k8s API to manage the Trino engine/catalog secrets). Always `false` on the migration Job, which never does |
| `serviceAccount.annotations` | `{}` | e.g. `eks.amazonaws.com/role-arn` or `iam.gke.io/gcp-service-account`, for cloud IAM federation |
| `extraEnv` | `[]` | Extra env vars appended to every workload's container |
| `extraVolumes` / `extraVolumeMounts` | `[]` | Extra volumes/mounts on every workload |
| `podAnnotations` / `podLabels` | `{}` | Extra pod-template annotations/labels merged onto every workload |

`env.trinoUrl` and `env.trinoDeployment` are enforced non-empty by
`values.schema.json`: the app reads both with a bare `ENV.fetch`, so a blank
value is a `KeyError` on the first engine start rather than at install time.

Every Deployment's pod template carries a `checksum/config` annotation and,
when the chart renders a Secret (`appSecrets.create: true`, or
`secret-chart-env.yaml` because `oidc.clientSecret` or
`admin.bootstrap.password` is set), a `checksum/secrets` annotation too, so a
`helm upgrade` that only changes a chart-rendered Secret still rolls the pods.
This does **not** cover the out-of-band Secret referenced by
`appSecrets.existingSecret` — the chart never sees its contents, so rotating it
still requires recycling the pods some other way (a new image tag, a manual
rollout restart, etc).

## License

Apache-2.0. See [LICENSE](../../../LICENSE).
