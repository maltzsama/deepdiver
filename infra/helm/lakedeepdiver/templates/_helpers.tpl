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
    resourceNames: [ "{{ include "lakedeepdiver.fullname" . }}-trino-catalog-secrets" ]
    verbs: [ "get", "update", "patch" ]
{{- end }}