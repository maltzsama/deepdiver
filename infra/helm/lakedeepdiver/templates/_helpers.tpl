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
Rules over the materialized catalog-credentials Secret. Used by
TrinoSecretMaterializer (app/services/trino_secret_materializer.rb), called
from CatalogSyncService independently of trino.provisioner - always granted.
*/}}
{{- define "lakedeepdiver.trinoSecretRules" -}}
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

{{/*
Rules to scale/patch the ephemeral Trino engine Deployment. Needed by both the
"chart" and "baleia" provisioners (BaleiaTrinoProvisioner < ChartTrinoProvisioner
only overrides create!), pointless only under "fake".
*/}}
{{- define "lakedeepdiver.trinoDeploymentRules" -}}
  # The Trino engine is an ephemeral Deployment (scaled 0/1) in the same or a
  # dedicated namespace (TRINO_NAMESPACE). The app patches it via kubeclient.
  - apiGroups: [ "apps" ]
    resources: [ "deployments" ]
    verbs: [ "get", "list", "patch" ]
  - apiGroups: [ "apps" ]
    resources: [ "deployments/scale" ]
    verbs: [ "get", "patch" ]
{{- end }}

{{/*
Rules granted to the app's ServiceAccount over the Trino engine and the
materialized catalog-credentials Secret. Used by the Role in the release
namespace and, when Trino lives elsewhere, by the Role created there.
*/}}
{{- define "lakedeepdiver.trinoRules" -}}
rules:
{{- if ne .Values.trino.provisioner "fake" }}
{{ include "lakedeepdiver.trinoDeploymentRules" . }}
{{- end }}
{{ include "lakedeepdiver.trinoSecretRules" . }}
{{- end }}

{{/*
Pod-template annotations shared by every workload: the ConfigMap checksum,
the checksum of chart-rendered Secrets (secret-app.yaml / secret-chart-env.yaml,
when either renders - NOT the out-of-band appSecrets.existingSecret, which the
chart never sees and so cannot checksum) and any operator-supplied
podAnnotations.
*/}}
{{- define "lakedeepdiver.podAnnotations" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- if or .Values.appSecrets.create (include "lakedeepdiver.hasChartEnvSecret" .) }}
checksum/secrets: {{ printf "%s%s" (include (print $.Template.BasePath "/secret-app.yaml") .) (include (print $.Template.BasePath "/secret-chart-env.yaml") .) | sha256sum }}
{{- end }}
{{- with .Values.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Renders one of the three Solid Queue worker Deployments (worker,
worker-engine, worker-freshness). They differ only in: name/labels/selector,
values key (replicaCount/resources/securityContext), the SOLID_QUEUE_CONFIG
file, the second SOLID_QUEUE_* env var, and an optional comment above it.
Takes a dict: root (the "." of the calling template), component (name
suffix / label value), selector (fully-qualified selector template name),
valuesKey (key under .Values), queueConfig, queueComment (optional),
queueEnvName, queueEnvValue.
*/}}
{{- define "lakedeepdiver.workerDeployment" -}}
{{- $root := .root }}
{{- $vals := index $root.Values .valuesKey }}
{{- if $vals.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "lakedeepdiver.fullname" $root }}-{{ .component }}
  labels:
    {{- include "lakedeepdiver.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ .component }}
spec:
  replicas: {{ $vals.replicaCount }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
  selector:
    matchLabels:
      {{- include .selector $root | nindent 6 }}
  template:
    metadata:
      annotations:
        {{- include "lakedeepdiver.podAnnotations" $root | nindent 8 }}
      labels:
        {{- include .selector $root | nindent 8 }}
        {{- with $root.Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      serviceAccountName: {{ include "lakedeepdiver.fullname" $root }}
      automountServiceAccountToken: {{ $root.Values.automountServiceAccountToken }}
      {{- with $root.Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $root.Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $root.Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $root.Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $root.Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      volumes:
        {{- if and $root.Values.internalCA.enabled $root.Values.internalCA.existingSecret }}
        - name: internal-ca
          secret:
            secretName: {{ $root.Values.internalCA.existingSecret | quote }}
            optional: true
            defaultMode: 0444
            items:
              - key: {{ $root.Values.internalCA.caKey | quote }}
                path: {{ base $root.Values.internalCA.mountFile | quote }}
        {{- end }}
        {{- with $root.Values.extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      containers:
        - name: solid-queue
          image: "{{ $root.Values.image.repository }}:{{ $root.Values.image.tag }}"
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
          command: ["./bin/jobs"]
          env:
            - name: K8S_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: HELM_RELEASE
              value: {{ $root.Release.Name | quote }}
            {{- with .queueComment }}
            # {{ . }}
            {{- end }}
            - name: SOLID_QUEUE_CONFIG
              value: {{ .queueConfig | quote }}
            - name: {{ .queueEnvName }}
              value: {{ .queueEnvValue | quote }}
            {{- with $root.Values.extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
            {{- if $root.Values.activeRecordEncryption.existingSecret }}
            - name: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ $root.Values.activeRecordEncryption.existingSecret | quote }}
                  key: primary_key
            - name: ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ $root.Values.activeRecordEncryption.existingSecret | quote }}
                  key: deterministic_key
            - name: ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
              valueFrom:
                secretKeyRef:
                  name: {{ $root.Values.activeRecordEncryption.existingSecret | quote }}
                  key: key_derivation_salt
            {{- end }}
          envFrom:
            {{- include "lakedeepdiver.envFrom" $root | nindent 12 }}
          volumeMounts:
            {{- if and $root.Values.internalCA.enabled $root.Values.internalCA.existingSecret }}
            - name: internal-ca
              mountPath: {{ dir $root.Values.internalCA.mountFile | quote }}
              readOnly: true
            {{- end }}
            {{- with $root.Values.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          livenessProbe:
            exec:
              command: [ "pgrep", "-f", "solid_queue" ]
            initialDelaySeconds: 30
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 3
          {{- with default $root.Values.securityContext $vals.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- toYaml $vals.resources | nindent 12 }}
{{- end }}
{{- end }}