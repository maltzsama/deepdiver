# lakedeepdiver Helm chart

Helm chart for the LakeDeepDiver control plane: the Rails 8 web app (Thrust + Puma), the
Solid Queue worker (`./bin/jobs`) and the minimal RBAC needed to scale the ephemeral
Trino engine.

## Quick start

```bash
# Build and push the image once per release (tag is x.y.z).
docker build -t registry.example.com/lakedeepdiver:0.1.0 .
docker push registry.example.com/lakedeepdiver:0.1.0

# Render and validate without a cluster.
helm lint infra/helm/lakedeepdiver
helm template lakedeepdiver infra/helm/lakedeepdiver \
  --values infra/helm/values/prod.yaml

# Install or upgrade on the cluster.
helm upgrade --install lakedeepdiver infra/helm/lakedeepdiver \
  --namespace lakedeepdiver --create-namespace \
  --values infra/helm/values/prod.yaml
```

## Parameters

| Value | Default | Meaning |
|---|---|---|
| `image.repository` / `image.tag` | `lakedeepdiver` / `0.1.0` | Image and pinned `x.y.z` tag (never `latest` in prod). |
| `replicaCount` | `1` | Web pod replicas. |
| `worker.enabled` / `worker.replicaCount` | `true` / `1` | Solid Queue supervisor (`./bin/jobs`) replicas. |
| `appSecrets.existingSecret` | — | Out-of-band Secret with `DATABASE_URL`, `DB_QUEUE_URL`, `RAILS_MASTER_KEY`, `SECRET_KEY_BASE`. |
| `appSecrets.create` | `false` | Render a Secret from `appSecrets.data` (local experiments only). |
| `internalCA.existingSecret` / `caKey` | — / `ca.crt` | Secret with the on-prem CA; mounted and exposed as `SSL_CERT_FILE`. |
| `env.trinoUrl` `trinoNamespace` `trinoDeployment` | — / release ns / `trino-coordinator` | Trino engine location and the Deployment to scale. |
| `env.jobConcurrency` | `1` | Solid Queue worker processes per pod. |
| `migrationJob.enabled` | `true` | Run `bin/rails db:migrate` as a pre-install/pre-upgrade hook Job. |

No certificate or credential is rendered by the chart. The two referenced Secrets
(`appSecrets.existingSecret` and `internalCA.externalSecret`) are created by ArgoCD,
SealedSecrets or any external controller.

## RBAC

The chart creates a ServiceAccount and a namespace-scoped `Role`/`RoleBinding`:

- `apps/deployments`: `get`, `list`, `patch`
- `apps/deployments/scale`: `get`, `patch`

This is exactly what `K8sClientFactory`+`TrinoK8sClient` need to bring the Trino
Deployment up (replicas 1) and down (replicas 0) in-cluster, using the pod's ServiceAccount
token and CA. The Role is scoped to the release namespace by default; if the engine lives in
another namespace (`env.trinoNamespace`), grant the equivalent Role/RoleBinding, or use a
ClusterRole, in that namespace.

## Internal CA trust

The Ruby app talks over HTTPS to Polaris/Nessie catalogs and runs SQL through the Trino
REST endpoint. When those are issued by the on-prem PKI, mount the root CA into the chart:

- Create a Secret holding the cert under key `ca.crt`.
- Set `internalCA.existingSecret`. The chart mounts it read-only to
  `/etc/ssl/certs/internal-ca.crt` and sets `SSL_CERT_FILE` so `Net::HTTP` trusts it.

Rotating the CA means rotating the Secret, no image rebuild.

## Migrations

`migrationJob` renders a `Job` annotated `helm.sh/hook: pre-install,pre-upgrade` with
`hook-delete-policy` and a small weight, so schema is guaranteed before web/worker pods
reach readiness. The image entrypoint still runs `db:prepare`, but only when started with
`rails server` by hand (not used in the chart).

## Image pipeline

Image build+push is **not** wired into GitHub Actions. This chart expects an external
pipeline (or manual `docker build`/`docker push`) to publish `image.repository:image.tag`;
the repo CI only lints and tests the application.