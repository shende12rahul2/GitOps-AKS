#!/usr/bin/env bash
# Admission policy tests (run against a kind cluster in CI).
set -euo pipefail
acr="${1:?acr login server}"
fail=0
expect() { # expect <allow|deny> <description> <manifest>
  local want="$1" desc="$2" manifest="$3" got
  if echo "$manifest" | kubectl apply --dry-run=server -f - >/dev/null 2>&1; then got=allow; else got=deny; fi
  if [ "$got" = "$want" ]; then echo "PASS $desc"; else echo "FAIL $desc (wanted $want, got $got)"; fail=1; fi
}
pod() { # pod <image> [extra securityContext yaml]
cat <<YAML
apiVersion: v1
kind: Pod
metadata: { name: policy-test, namespace: apps }
spec:
  securityContext: { runAsNonRoot: true, runAsUser: 10001, seccompProfile: { type: RuntimeDefault } }
  containers:
    - name: c
      image: $1
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: [ALL] }
        ${2:-}
YAML
}
digest="sha256:$(printf '0%.0s' {1..64})"
expect allow "digest-pinned image from the ACR"            "$(pod "$acr/user-service@$digest")"
expect deny  "tag-only image from the ACR"                  "$(pod "$acr/user-service:latest")"
expect deny  "image from Docker Hub"                        "$(pod "docker.io/library/nginx@$digest")"
expect deny  "privileged container (Pod Security restricted)" "$(pod "$acr/user-service@$digest" "privileged: true")"
exit "$fail"
