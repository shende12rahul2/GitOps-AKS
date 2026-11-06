#!/usr/bin/env bash
# Creates the five persona security groups. Run once by an Entra administrator
# (Groups Administrator or equivalent). The CI identities deliberately have no
# Microsoft Graph permissions, which is why this is a script and not Terraform.
# Output: the object IDs to paste into environments/<env>/platform/terraform.tfvars.
set -euo pipefail
project="${1:-akspoc}"
declare -A groups=(
  [platform_admins]="Platform administrators: cluster-admin, state recovery, Key Vault secrets"
  [devops]="DevOps engineers: operate workloads, Argo CD sync, read infrastructure"
  [developers]="Developers: application code and DAG pull requests, read-only cluster access"
  [qa]="QA engineers: read-only workloads/logs, trigger test DAGs"
  [readers]="Read-only users"
)
echo "entra_group_object_ids = {"
for key in platform_admins devops developers qa readers; do
  name="grp-${project}-${key//_/-}"
  id=$(az ad group list --display-name "$name" --query "[0].id" -o tsv)
  if [ -z "$id" ]; then
    id=$(az ad group create --display-name "$name" --mail-nickname "$name" --description "${groups[$key]}" --query id -o tsv)
  fi
  printf '  %-15s = "%s"\n' "$key" "$id"
done
echo "}"
