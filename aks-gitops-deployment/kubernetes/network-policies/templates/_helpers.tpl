{{- define "np.dns" -}}
- to:
    - namespaceSelector:
        matchLabels: { kubernetes.io/metadata.name: kube-system }
      podSelector:
        matchLabels: { k8s-app: kube-dns }
  ports:
    - { port: 53, protocol: UDP }
    - { port: 53, protocol: TCP }
{{- end -}}

{{- define "np.internet443" -}}
- to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
          {{- toYaml .Values.privateRanges | nindent 10 }}
  ports:
    - { port: 443, protocol: TCP }
{{- end -}}

{{- define "np.ingressSource" -}}
{{- if eq .Values.global.ingress.mode "agic" }}
- ipBlock:
    cidr: {{ .Values.global.ingress.gatewaySubnetCidr }}
{{- else }}
- namespaceSelector:
    matchLabels: { kubernetes.io/metadata.name: ingress }
{{- end }}
{{- end -}}
