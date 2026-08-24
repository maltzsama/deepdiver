{{/*
Expand the name of the chart.
*/}}
{{- define "lakedeepdiver.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "lakedeepdiver.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "lakedeepdiver.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "lakedeepdiver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels for the web Deployment (must be unique per Deployment).
*/}}
{{- define "lakedeepdiver.webSelector" -}}
app.kubernetes.io/name: {{ include "lakedeepdiver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: web
{{- end }}

{{/*
Selector labels for the Solid Queue worker Deployment.
*/}}
{{- define "lakedeepdiver.workerSelector" -}}
app.kubernetes.io/name: {{ include "lakedeepdiver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Selector labels for the freshness worker Deployment.
*/}}
{{- define "lakedeepdiver.workerFreshnessSelector" -}}
app.kubernetes.io/name: {{ include "lakedeepdiver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: worker-freshness
{{- end }}

{{/*
Selector labels for the engine worker Deployment.
*/}}
{{- define "lakedeepdiver.workerEngineSelector" -}}
app.kubernetes.io/name: {{ include "lakedeepdiver.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: worker-engine
{{- end }}

{{/*
Name of the Secret into which the app materializes catalog credentials.
Single source of truth: it is both authorized by the Role (resourceNames) and
handed to the app as TRINO_CATALOG_SECRET_NAME. The app must never compute it
itself - when it did, it derived the name from the release name while the Role
authorized the fullname, and every get returned 403.
*/}}
{{- define "lakedeepdiver.trinoSecretName" -}}
{{- printf "%s-trino-catalog-secrets" (include "lakedeepdiver.fullname" .) }}
{{- end }}

{{/*
Non-empty when the chart renders the <fullname>-chart-env Secret, i.e. when the
operator supplied a sensitive value through chart values. Every pod must mount
it whenever it exists: config/initializers/devise.rb runs ENV.fetch on the OIDC
vars in EVERY process (web and all three workers), so a missing
OIDC_CLIENT_SECRET while SSO_ENABLED=true is a boot-time KeyError, not just a
broken login.
*/}}
{{- define "lakedeepdiver.hasChartEnvSecret" -}}
{{- if or (and .Values.oidc.issuer .Values.oidc.clientSecret) (and .Values.admin.bootstrap.email .Values.admin.bootstrap.password) }}true{{ end }}
{{- end }}

{{/*
The envFrom entries shared by every workload: the ConfigMap, the out-of-band
app Secret and, when present, the chart-env Secret.
*/}}
{{- define "lakedeepdiver.envFrom" -}}
- configMapRef:
    name: {{ include "lakedeepdiver.fullname" . }}
{{- if .Values.appSecrets.existingSecret }}
- secretRef:
    name: {{ .Values.appSecrets.existingSecret | quote }}
{{- else if .Values.appSecrets.create }}
- secretRef:
    name: {{ include "lakedeepdiver.fullname" . }}-app
{{- end }}
{{- if include "lakedeepdiver.hasChartEnvSecret" . }}
- secretRef:
    name: {{ include "lakedeepdiver.fullname" . }}-chart-env
{{- end }}
{{- end }}

{{/*
Rules granted to the app's ServiceAccount over the Trino engine and the
materialized catalog-credentials Secret. Used by the Role in the release
namespace and, when Trino lives elsewhere, by the Role created there.
*/}}
{{- define "lakedeepdiver.trinoRules" -}}
rules:
  # The Trino engine is an ephemeral Deployment (scaled 0/1) in the same or a
  # dedicated namespace (TRINO_NAMESPACE). The app patches it via kubeclient.
  - apiGroups: [ "apps" ]
    resources: [ "deployments" ]
    verbs: [ "get", "list", "patch" ]
  - apiGroups: [ "apps" ]
    resources: [ "deployments/scale" ]
    verbs: [ "get", "patch" ]
  # Catalog credentials are materialized as a Secret that the Trino plugin
  # mounts at /etc/baleia/secrets. The app creates/updates this Secret.
  # Scoped to the materialized Secret only (resourceNames is ignored for
  # create, so the create rule stays separate) so the app's own Secret -
  # DATABASE_URL, RAILS_MASTER_KEY, encryption keys - is never reachable.
  - apiGroups: [ "" ]
    resources: [ "secrets" ]
    verbs: [ "create" ]
  - apiGroups: [ "" ]
    resources: [ "secrets" ]
    resourceNames: [ {{ include "lakedeepdiver.trinoSecretName" . | quote }} ]
    verbs: [ "get", "update", "patch" ]
{{- end }}