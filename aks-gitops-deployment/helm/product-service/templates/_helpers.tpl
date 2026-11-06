{{/* Chart name (the service name). */}}
{{- define "svc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "svc.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "svc.name" . -}}
{{- end -}}
{{- end -}}

{{- define "svc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "svc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "svc.labels" -}}
{{ include "svc.selectorLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: aks-poc
environment: {{ .Values.global.environment | default "local" }}
{{- end -}}

{{/* The service account name is the federated-credential subject: keep it stable. */}}
{{- define "svc.serviceAccountName" -}}
{{- default (include "svc.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/* Immutable image reference: repository@sha256:... (tags only when explicitly allowed). */}}
{{- define "svc.image" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.image.digest) -}}
{{- fail "image.digest must look like sha256:<64 hex chars>" -}}
{{- end -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else if .Values.image.allowTagOnly -}}
{{- printf "%s:%s" $repo (required "image.tag is required when no digest is set" .Values.image.tag) -}}
{{- else -}}
{{- fail "image.digest is required: deployments must reference immutable digests (set image.allowTagOnly=true only for local testing)" -}}
{{- end -}}
{{- end -}}

{{/* Workload identity client ID: explicit value, else the environment contract. */}}
{{- define "svc.clientId" -}}
{{- $fromGlobal := dig (include "svc.name" .) "clientId" "" (.Values.global.workloadIdentities | default dict) -}}
{{- default $fromGlobal .Values.workloadIdentity.clientId -}}
{{- end -}}

{{- define "svc.dbUser" -}}
{{- $fromGlobal := dig (include "svc.name" .) "name" "" (.Values.global.workloadIdentities | default dict) -}}
{{- default $fromGlobal .Values.database.user -}}
{{- end -}}

{{- define "svc.redisHost" -}}
{{- default (dig "host" "" (.Values.global.redis | default dict)) .Values.redis.host -}}
{{- end -}}

{{- define "svc.dbHost" -}}
{{- default (dig "host" "" (.Values.global.postgres | default dict)) .Values.database.host -}}
{{- end -}}
