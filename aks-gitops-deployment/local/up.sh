#!/usr/bin/env bash
# Local k3s test bed for the application + GitOps parts of the POC.
#
#   local/up.sh                      # Argo CD mode (GitOps, syncs from GitHub)
#   MODE=helm local/up.sh            # no Argo CD: helm install the charts directly
#   WITH_AIRFLOW=1 local/up.sh       # also Airflow 3.2.2 (needs ~16 GB RAM laptop)
#
# Env: REPO_URL (default: git origin), REVISION (default: current branch),
#      GITHUB_TOKEN (private repo, read-only PAT), IMPORT=auto|k3s|k3d|none,
#      APP_DIR (path to aks-microservices-app when the repos are split),
#      BUILDER=auto|docker|buildah (buildah = no Docker daemon needed),
#      EXTRA_BUILD_ARGS (extra flags for the image build, e.g. a corporate proxy CA mount),
#      AIRFLOW_CHART (local chart directory instead of the apache-airflow Helm repo),
#      AIRFLOW_EXTRA_VALUES (extra values file for Airflow, e.g. proxy settings for git-sync).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"            # .../aks-gitops-deployment/local
gitops="$(dirname "$here")"
root="$(git -C "$gitops" rev-parse --show-toplevel)"
prefix="${gitops#"$root"}"; prefix="${prefix#/}"; prefix="${prefix:+$prefix/}"   # "aks-gitops-deployment/" in the monorepo
APP_DIR="${APP_DIR:-$root/aks-microservices-app}"
MODE="${MODE:-argocd}"; WITH_AIRFLOW="${WITH_AIRFLOW:-0}"; IMPORT="${IMPORT:-auto}"
REPO_URL="${REPO_URL:-$(git -C "$root" remote get-url origin)}"
REPO_URL="$(sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##; s#^http://local_proxy@127\.0\.0\.1:[0-9]+/git/#https://github.com/#' <<<"$REPO_URL").git"
REVISION="${REVISION:-$(git -C "$root" rev-parse --abbrev-ref HEAD)}"
SERVICES=(frontend user-service product-service order-service notification-service)
k() { kubectl "$@"; }
log() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"; }

log "Preflight"
for t in kubectl helm git python3; do command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }; done
BUILDER="${BUILDER:-auto}"
if [ "$BUILDER" = auto ]; then
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then BUILDER=docker
  elif command -v buildah >/dev/null; then BUILDER=buildah
  else echo "need docker (running) or buildah"; exit 1; fi
fi
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO=sudo
k get nodes -o wide
[ -d "$APP_DIR/services" ] || { echo "APP_DIR not found: $APP_DIR"; exit 1; }
echo "mode=$MODE airflow=$WITH_AIRFLOW repo=$REPO_URL revision=$REVISION prefix=${prefix:-<none>}"

log "Build images with $BUILDER (same Dockerfiles as CI)"
images=()
build() { # dockerfile tag
  # shellcheck disable=SC2086
  if [ "$BUILDER" = docker ]; then docker build -q ${EXTRA_BUILD_ARGS:-} -f "$1" -t "$2" "$APP_DIR"
  else buildah bud -q --layers ${EXTRA_BUILD_ARGS:-} -f "$1" -t "$2" "$APP_DIR" >/dev/null; fi
  images+=("$2"); echo "built $2"
}
for s in "${SERVICES[@]}"; do build "$APP_DIR/services/$s/Dockerfile" "aks-poc/$s:local"; done
build "$APP_DIR/tools/db-bootstrap/Dockerfile" aks-poc/db-bootstrap:local
[ "$WITH_AIRFLOW" = 1 ] && build "$APP_DIR/airflow/Dockerfile" aks-poc/airflow:local

log "Import images into the cluster runtime"
if [ "$IMPORT" = auto ]; then
  if command -v k3d >/dev/null && k3d cluster list 2>/dev/null | grep -q .; then IMPORT=k3d
  elif command -v k3s >/dev/null; then IMPORT=k3s
  else IMPORT=none; fi
fi
case "$IMPORT" in
  k3s)
    if [ "$BUILDER" = docker ]; then docker save "${images[@]}" | $SUDO k3s ctr images import -
    else
      for i in "${images[@]}"; do
        tar=$(mktemp -u).tar; buildah push -q "$i" "oci-archive:$tar:docker.io/$i" >/dev/null
        $SUDO k3s ctr images import "$tar" >/dev/null && echo "imported $i"; rm -f "$tar"
      done
    fi ;;
  k3d) k3d image import -c "${K3D_CLUSTER:-$(k3d cluster list -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["name"])')}" "${images[@]}" ;;
  none) echo "skipping import (runtime shares Docker's image store, e.g. Rancher Desktop with dockerd)" ;;
esac

log "Namespaces and local secrets (generated once, never in Git)"
k apply -f "$here/infra/00-namespaces.yaml"
secret() { # ns name key=value...
  local ns="$1" name="$2"; shift 2
  k -n "$ns" get secret "$name" >/dev/null 2>&1 && return 0
  local args=(); for kv in "$@"; do args+=(--from-literal="$kv"); done
  k -n "$ns" create secret generic "$name" "${args[@]}" >/dev/null && echo "created $ns/$name"
}
secret data pg-admin "password=$(rand 32)"
secret data db-passwords "user-service=$(rand)" "product-service=$(rand)" "order-service=$(rand)" "airflow=$(rand)"
# Services read their own password from the same values in the apps namespace.
k -n data get secret db-passwords -o json | python3 -c '
import sys, json
s = json.load(sys.stdin)
print(json.dumps({"apiVersion": "v1", "kind": "Secret", "type": "Opaque",
  "metadata": {"name": "db-passwords", "namespace": "apps"},
  "data": {k: v for k, v in s["data"].items() if k != "airflow"}}))' | k apply -f - >/dev/null
secret apps internal-api-key "internal-api-key=$(rand 48)"

deploy_helm() {
  log "Deploy local infra (PostgreSQL, Redis, storage, db-bootstrap, ingress)"
  k -n data delete job db-bootstrap --ignore-not-found >/dev/null
  k apply -f "$here/infra/"
  k -n data rollout status deploy/postgres --timeout=180s
  k -n data rollout status deploy/redis --timeout=120s
  k -n data wait --for=condition=complete job/db-bootstrap --timeout=300s
  k -n data logs job/db-bootstrap 2>/dev/null | tail -1 || true
  log "Helm install the five charts"
  for s in "${SERVICES[@]}"; do
    k -n apps delete job "$s-migrate" --ignore-not-found >/dev/null
    helm upgrade --install "$s" "$gitops/helm/$s" -n apps -f "$here/values/global.yaml" -f "$here/values/$s.yaml" >/dev/null && echo "installed $s"
  done
}

deploy_argocd() {
  log "Install Argo CD (chart 10.14.0)"
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm upgrade --install argocd argo/argo-cd --version 10.14.0 -n argocd --create-namespace \
    -f "$here/argocd/argocd-values.yaml" --wait --timeout 10m >/dev/null
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    k -n argocd create secret generic gitops-repo --from-literal=type=git --from-literal=url="$REPO_URL" \
      --from-literal=username=x-access-token --from-literal=password="$GITHUB_TOKEN" --dry-run=client -o yaml \
      | k label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | k apply -f - >/dev/null
    echo "repository credentials configured"
  fi
  log "Register the local Applications (source: $REPO_URL @ $REVISION)"
  sed -e "s#__REPO_URL__#$REPO_URL#g" -e "s#__REVISION__#$REVISION#g" -e "s#__PREFIX__#$prefix#g" \
    "$here/argocd/applications.yaml" | k apply -f -
  log "Waiting for Argo CD to sync (db-bootstrap, then services)"
  for i in $(seq 1 60); do
    ready=$(k -n apps get deploy -o jsonpath='{range .items[*]}{.status.readyReplicas}{"\n"}{end}' 2>/dev/null | grep -c '^[1-9]' || true)
    [ "$ready" -ge 5 ] && break; sleep 10
  done
  k -n argocd get applications
}

deploy_airflow() {
  log "Airflow 3.2.2 (optional)"
  k create namespace airflow --dry-run=client -o yaml | k apply -f - >/dev/null
  pw=$(k -n data get secret db-passwords -o jsonpath='{.data.airflow}' | base64 -d)
  secret airflow airflow-metadata "connection=postgresql://airflow:${pw}@postgres.data.svc.cluster.local:5432/airflow_metadata"
  secret airflow airflow-broker-url "connection=redis://redis.data.svc.cluster.local:6379/0"
  k -n apps get secret internal-api-key -o json | python3 -c '
import sys, json
s = json.load(sys.stdin)
print(json.dumps({"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "internal-api-key", "namespace": "airflow"}, "data": s["data"]}))' | k apply -f - >/dev/null
  secret airflow airflow-local-admin "password=$(rand 20)"
  extra=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    secret airflow airflow-git-credentials "GITSYNC_USERNAME=x-access-token" "GITSYNC_PASSWORD=$GITHUB_TOKEN" "GIT_SYNC_USERNAME=x-access-token" "GIT_SYNC_PASSWORD=$GITHUB_TOKEN"
    extra+=(--set dags.gitSync.credentialsSecret=airflow-git-credentials)
  fi
  app_prefix=""; [ -d "$root/aks-microservices-app" ] && app_prefix="aks-microservices-app/"
  app_repo="${APP_REPO_URL:-$REPO_URL}"
  values=$(mktemp); sed -e "s#__REPO_URL__#$app_repo#g" -e "s#__REVISION__#$REVISION#g" -e "s#__APP_PREFIX__#$app_prefix#g" "$here/values/airflow.yaml" > "$values"
  chart=(apache-airflow/airflow --version 1.22.0)
  if [ -n "${AIRFLOW_CHART:-}" ]; then chart=("$AIRFLOW_CHART")
  else helm repo add apache-airflow https://airflow.apache.org >/dev/null 2>&1 || true; fi
  [ -n "${AIRFLOW_EXTRA_VALUES:-}" ] && extra+=(-f "$AIRFLOW_EXTRA_VALUES")
  helm upgrade --install airflow "${chart[@]}" -n airflow -f "$values" "${extra[@]}" \
    --set createUserJob.defaultUser.password="$(k -n airflow get secret airflow-local-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --timeout 15m >/dev/null
  rm -f "$values"
  echo "Airflow UI: kubectl -n airflow port-forward svc/airflow-api-server 8080:8080  (user admin, password: kubectl -n airflow get secret airflow-local-admin -o jsonpath='{.data.password}' | base64 -d)"
}

case "$MODE" in helm) deploy_helm ;; argocd) deploy_argocd ;; *) echo "MODE must be helm or argocd"; exit 1 ;; esac
for s in "${SERVICES[@]}"; do k -n apps rollout status "deploy/$s" --timeout=300s; done
[ "$WITH_AIRFLOW" = 1 ] && deploy_airflow

log "Ready"
echo "Frontend:  http://app.localtest.me"
echo "APIs:      http://app.localtest.me/api/{users,products,orders,notifications}"
[ "$MODE" = argocd ] && echo "Argo CD:   http://argocd.localtest.me  (admin / $(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d))"
echo "Tests:     local/test.sh"
