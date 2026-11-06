#!/usr/bin/env bash
# Cross-node Azure Files validation (Phase 10). Runs two short-lived pods on two
# DIFFERENT user-pool nodes that mount the same RWX claim, then:
#   1-2. pod A on node 1, pod B on node 2
#   3.   A writes a file           4. B reads it
#   5.   B modifies it             6. A reads the update
#   7.   both pods are deleted and recreated (restart)
#   8.   the pods swap nodes       9. the file is still there and intact
# Uses the notification-service image (digest from environments/<env>/apps) so
# the admission policy (ACR + digest) and Pod Security "restricted" both pass.
set -euo pipefail
env="${1:?env}"; ns=apps; claim=shared-files-pvc
here="$(cd "$(dirname "$0")/.." && pwd)"
img="$(yq -r '.image.repository + "@" + .image.digest' "$here/environments/$env/apps/notification-service.yaml")"
mapfile -t nodes < <(kubectl get nodes -l workload-class=apps -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[ "${#nodes[@]}" -ge 2 ] || { echo "need >= 2 user nodes, found ${#nodes[@]}"; exit 1; }
n1="${nodes[0]}"; n2="${nodes[1]}"
file="/mnt/shared/common/cross-node-test-$(date +%s).txt"

pod() { # name node
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: $ns
  labels: { app.kubernetes.io/name: shared-storage-test }
spec:
  nodeName: $2
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext: { runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001, seccompProfile: { type: RuntimeDefault } }
  containers:
    - name: t
      image: $img
      command: ["python", "-c", "import time; time.sleep(900)"]
      securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: [ALL] } }
      resources: { requests: { cpu: 10m, memory: 32Mi }, limits: { cpu: 100m, memory: 64Mi } }
      volumeMounts: [{ name: shared, mountPath: /mnt/shared }]
  volumes:
    - name: shared
      persistentVolumeClaim: { claimName: $claim }
YAML
kubectl -n $ns wait --for=condition=Ready pod/$1 --timeout=180s >/dev/null
}
py() { kubectl -n $ns exec "$1" -- python -c "$2"; }
cleanup() { kubectl -n $ns delete pod shared-a shared-b --ignore-not-found --wait=true >/dev/null; }
trap cleanup EXIT

echo "1-2. pod A on $n1, pod B on $n2"; pod shared-a "$n1"; pod shared-b "$n2"
echo "3.   A writes";   py shared-a "open('$file','w').write('written by A on $n1\n')"
echo "4.   B reads:     $(py shared-b "print(open('$file').read().strip())")"
echo "5.   B modifies"; py shared-b "open('$file','a').write('modified by B on $n2\n')"
echo "6.   A reads:     $(py shared-a "print(open('$file').read().strip().replace(chr(10),' | '))")"
echo "7.   restart both pods"; cleanup; pod shared-a "$n1"; pod shared-b "$n2"
echo "8.   swap nodes (A -> $n2, B -> $n1)"; cleanup; pod shared-a "$n2"; pod shared-b "$n1"
content="$(py shared-a "print(open('$file').read())")"
grep -q "written by A" <<<"$content" && grep -q "modified by B" <<<"$content" \
  && echo "9.   PASS: file persisted across restarts and node moves" || { echo "9.   FAIL: $content"; exit 1; }
py shared-b "import os; os.remove('$file')"
