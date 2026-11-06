{{/* Ingress class + annotations for the selected ingress mode. */}}
{{- define "ing.annotations" -}}
{{- $root := index . 0 -}}
{{- $private := index . 1 -}}
{{- $probe := index . 2 -}}
{{- $ns := index . 3 -}}
cert-manager.io/cluster-issuer: {{ $root.Values.tls.issuer }}
{{- if eq $root.Values.global.ingress.mode "agic" }}
appgw.ingress.kubernetes.io/ssl-redirect: "true"
appgw.ingress.kubernetes.io/use-private-ip: {{ $private | quote }}
appgw.ingress.kubernetes.io/backend-protocol: http
appgw.ingress.kubernetes.io/health-probe-path: {{ $probe }}
appgw.ingress.kubernetes.io/request-timeout: {{ $root.Values.agic.requestTimeoutSeconds | quote }}
appgw.ingress.kubernetes.io/connection-draining: "true"
appgw.ingress.kubernetes.io/connection-draining-timeout: {{ $root.Values.agic.connectionDrainingSeconds | quote }}
{{- else }}
traefik.ingress.kubernetes.io/router.entrypoints: websecure
traefik.ingress.kubernetes.io/router.tls: "true"
traefik.ingress.kubernetes.io/router.middlewares: {{ printf "%s-security-headers@kubernetescrd" $ns }}
{{- end }}
{{- end -}}

{{- define "ing.className" -}}
{{- if eq .Values.global.ingress.mode "agic" -}}{{ .Values.agic.className }}{{- else -}}traefik{{- end -}}
{{- end -}}
