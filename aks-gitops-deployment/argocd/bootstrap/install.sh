#!/usr/bin/env bash
# Phase 6 - GitOps bootstrap (run once per cluster by a platform administrator).
#
# The AKS API server is private, so this runs either from the jumpbox (inside the
# VNet) or through `az aks command invoke`, which executes the commands inside the
# cluster without any network path to the API server.
#
# Usage:
#   ./install.sh <env> <resource-group> <cluster-name> [--invoke]
# Requires: az (logged in as a platform admin), kubectl + kubelogin, helm 3.
set -euo pipefail
env="${1:?env}"; rg="${2:?resource group}"; cluster="${3:?cluster}"; mode="${4:-}"
here="$(cd "$(dirname "$0")" && pwd)"; repo_root="$(cd "$here/../.." && pwd)"
chart_version="10.14.0"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

cp "$here/values.yaml" "$work/values.yaml"
cp "$repo_root/environments/$env/argocd-values.yaml" "$work/env-values.yaml"
cp "$repo_root/environments/$env/argocd.yaml" "$work/apps-values.yaml"
repo_url=$(awk '/^repoURL:/ {print $2}' "$work/apps-values.yaml")
vault=$(awk '/keyVaultName:/ {print $2}' "$repo_root/environments/$env/infrastructure.yaml")

# Root Application (app-of-apps) for this environment.
sed -e "s#__ENV__#$env#g" -e "s#__REPO_URL__#$repo_url#g" "$here/root-app.yaml" > "$work/root-app.yaml"

# Private GitOps repository: read-only deploy key from Key Vault (data layer
# placeholder "argocd-repo-ssh-key", set with scripts/set-operator-secret.sh).
if [[ "$repo_url" == git@* ]]; then
  az keyvault secret show --vault-name "$vault" --name argocd-repo-ssh-key --query value -o tsv > "$work/repo-key"
  kubectl create secret generic gitops-repo --dry-run=client -o yaml -n argocd \
    --from-literal=type=git --from-literal=url="$repo_url" --from-file=sshPrivateKey="$work/repo-key" \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml > "$work/repo-secret.yaml"
  rm -f "$work/repo-key"
fi

cat > "$work/run.sh" <<RUN
set -euo pipefail
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace argocd pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/warn=restricted --overwrite
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm upgrade --install argocd argo/argo-cd --version $chart_version -n argocd -f values.yaml -f env-values.yaml --wait --timeout 10m
[ -f repo-secret.yaml ] && kubectl apply -f repo-secret.yaml
kubectl apply -f root-app.yaml
kubectl -n argocd get applications
RUN

if [ "$mode" = "--invoke" ]; then
  # Uploads the working directory and runs inside the cluster (no network path needed).
  az aks command invoke -g "$rg" -n "$cluster" --command "bash run.sh" --file "$work/."
else
  az aks get-credentials -g "$rg" -n "$cluster" --overwrite-existing
  kubelogin convert-kubeconfig -l azurecli
  (cd "$work" && bash run.sh)
fi
echo "Argo CD bootstrapped. UI: https://argocd.<zone> (private), CLI: argocd login argocd.<zone> --sso --grpc-web"
