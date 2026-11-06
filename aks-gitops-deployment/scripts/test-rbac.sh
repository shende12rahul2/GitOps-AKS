#!/usr/bin/env bash
# RBAC verification (Phase 10). Two layers:
#  1. Azure RBAC for Kubernetes / Azure resources: lists the role assignments of
#     each persona group (what Terraform granted).
#  2. Kubernetes authorization: `kubectl auth can-i` for the signed-in user. Sign
#     in as a member of each persona (az login + kubelogin) and compare with
#     docs/rbac-matrix.md. Kubernetes RoleBindings are also checked through
#     impersonation (requires cluster-admin, i.e. a platform administrator).
set -euo pipefail
env="${1:?env}"; rg="${2:?platform resource group}"; cluster="${3:?cluster name}"
here="$(cd "$(dirname "$0")/.." && pwd)"
aks_id=$(az aks show -g "$rg" -n "$cluster" --query id -o tsv)

echo "== Azure role assignments per persona group"
for p in platformAdmins devops developers qa readers; do
  gid=$(yq -r ".global.entraGroups.$p" "$here/environments/$env/infrastructure.yaml")
  echo "-- $p ($gid)"
  az role assignment list --assignee "$gid" --all --query "[].{role:roleDefinitionName, scope:scope}" -o tsv \
    | sed "s#$aks_id#<aks>#" | sort
done

echo "== Signed-in user ($(az account show --query user.name -o tsv))"
for check in "get pods -n apps" "get pods/log -n apps" "get secrets -n apps" "create deployments -n apps" \
             "delete pods -n apps" "create pods/exec -n apps" "get pods -n airflow" "get nodes" "create namespaces"; do
  printf '%-32s %s\n' "$check" "$(kubectl auth can-i $check 2>/dev/null || true)"
done

if kubectl auth can-i impersonate groups >/dev/null 2>&1; then
  echo "== Kubernetes RoleBindings (impersonation)"
  dev=$(yq -r .global.entraGroups.developers "$here/environments/$env/infrastructure.yaml")
  ops=$(yq -r .global.entraGroups.devops "$here/environments/$env/infrastructure.yaml")
  printf 'developers get pods/log apps:       %s\n' "$(kubectl auth can-i get pods/log -n apps --as rbac-test --as-group "$dev" || true)"
  printf 'developers delete pods apps:        %s\n' "$(kubectl auth can-i delete pods -n apps --as rbac-test --as-group "$dev" || true)"
  printf 'devops patch deployments apps:      %s\n' "$(kubectl auth can-i patch deployments -n apps --as rbac-test --as-group "$ops" || true)"
  printf 'devops get secrets apps (expect no): %s\n' "$(kubectl auth can-i get secrets -n apps --as rbac-test --as-group "$ops" || true)"
fi
