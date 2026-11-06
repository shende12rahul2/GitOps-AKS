{{- define "apps.syncPolicy" -}}
syncPolicy:
  {{- if .Values.sync.automated }}
  automated:
    prune: {{ .Values.sync.prune }}
    selfHeal: {{ .Values.sync.selfHeal }}
  {{- end }}
  syncOptions:
    - CreateNamespace=false
    - PruneLast=true
    - ServerSideApply=true
  retry:
    limit: 5
    backoff: { duration: 15s, factor: 2, maxDuration: 5m }
{{- end -}}

{{/* Value files shared by every chart in this repository. */}}
{{- define "apps.envValues" -}}
- ../../environments/{{ .Values.environment }}/infrastructure.yaml
{{- end -}}
