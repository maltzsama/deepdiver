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