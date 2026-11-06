#!/usr/bin/env bash
# Creates the Entra ID app registrations used for single sign-on:
#   - Argo CD: OIDC with *workload identity federation* (no client secret).
#   - Airflow: OAuth (Flask AppBuilder). FAB needs a client secret, which is
#     written straight to Key Vault (secret airflow-oauth-client-secret).
# Both apps require assignment, so only the persona groups can sign in.
#
# Usage: create-app-registrations.sh <env> <aks-oidc-issuer-url> <app-dns-zone> <key-vault-name> <project>
set -euo pipefail
env="${1:?env}"; issuer="${2:?AKS OIDC issuer (terraform output aks_oidc_issuer_url)}"
zone="${3:-poc.example.com}"; vault="${4:?key vault name}"; project="${5:-akspoc}"
here="$(cd "$(dirname "$0")" && pwd)"

group_ids() {
  for key in platform-admins devops developers qa readers; do
    az ad group list --display-name "grp-${project}-${key}" --query "[0].id" -o tsv
  done
}

ensure_app() { # name -> appId
  local name="$1" id
  id=$(az ad app list --display-name "$name" --query "[0].appId" -o tsv)
  [ -n "$id" ] || id=$(az ad app create --display-name "$name" --sign-in-audience AzureADMyOrg --query appId -o tsv)
  az ad sp show --id "$id" >/dev/null 2>&1 || az ad sp create --id "$id" --output none
  # Emit group object IDs in the token (filtered to assigned groups below).
  az ad app update --id "$id" --set groupMembershipClaims=ApplicationGroup --output none
  echo "$id"
}

assign_groups() { # appId
  local sp; sp=$(az ad sp show --id "$1" --query id -o tsv)
  az ad sp update --id "$1" --set appRoleAssignmentRequired=true --output none
  for gid in $(group_ids); do
    az rest --method post --url "https://graph.microsoft.com/v1.0/servicePrincipals/${sp}/appRoleAssignedTo" \
      --body "{\"principalId\":\"${gid}\",\"resourceId\":\"${sp}\",\"appRoleId\":\"00000000-0000-0000-0000-000000000000\"}" \
      --output none 2>/dev/null || true # already assigned
  done
}

# --- Argo CD ---------------------------------------------------------------------
argocd_app=$(ensure_app "argocd-${project}-${env}")
az ad app update --id "$argocd_app" \
  --web-redirect-uris "https://argocd.${zone}/auth/callback" \
  --public-client-redirect-uris "http://localhost:8085/auth/callback" \
  --enable-id-token-issuance true --output none
az ad app federated-credential create --id "$argocd_app" --parameters "{
  \"name\": \"aks-${env}-argocd-server\",
  \"issuer\": \"${issuer}\",
  \"subject\": \"system:serviceaccount:argocd:argocd-server\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}" --output none 2>/dev/null || echo "federated credential already exists"
assign_groups "$argocd_app"

# --- Airflow -----------------------------------------------------------------------
# Flask AppBuilder maps the token's "roles" claim (app roles) to Airflow roles:
# Airflow.Admin -> Admin, Airflow.Op -> Op, Airflow.User -> User, Airflow.Viewer -> Viewer.
airflow_app=$(ensure_app "airflow-${project}-${env}")
roles_file=$(mktemp)
python3 - "$roles_file" <<'PY'
import json, sys, uuid
roles = [("Airflow.Admin", "Platform administrators"), ("Airflow.Op", "DevOps engineers"),
         ("Airflow.User", "Developers and QA (trigger DAGs, view logs)"), ("Airflow.Viewer", "Read-only users")]
json.dump([{"allowedMemberTypes": ["User"], "description": d, "displayName": v, "isEnabled": True,
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, "aks-poc/" + v)), "value": v} for v, d in roles], open(sys.argv[1], "w"))
PY
az ad app update --id "$airflow_app" \
  --web-redirect-uris "https://airflow.${zone}/auth/oauth-authorized/azure" \
  --enable-id-token-issuance true --app-roles "@${roles_file}" --output none
rm -f "$roles_file"
airflow_sp=$(az ad sp show --id "$airflow_app" --query id -o tsv)
az ad sp update --id "$airflow_app" --set appRoleAssignmentRequired=true --output none
assign_role() { # group-key role-value
  local gid rid
  gid=$(az ad group list --display-name "grp-${project}-$1" --query "[0].id" -o tsv)
  rid=$(az ad sp show --id "$airflow_app" --query "appRoles[?value=='$2'].id | [0]" -o tsv)
  az rest --method post --url "https://graph.microsoft.com/v1.0/servicePrincipals/${airflow_sp}/appRoleAssignedTo" \
    --body "{\"principalId\":\"${gid}\",\"resourceId\":\"${airflow_sp}\",\"appRoleId\":\"${rid}\"}" --output none 2>/dev/null || true
}
assign_role platform-admins Airflow.Admin
assign_role devops Airflow.Op
assign_role developers Airflow.User
assign_role qa Airflow.User
assign_role readers Airflow.Viewer
secret_file=$(mktemp); trap 'rm -f "$secret_file"' EXIT
az ad app credential reset --id "$airflow_app" --display-name "airflow-${env}" --years 1 --query password -o tsv > "$secret_file"
"$here/../../scripts/set-operator-secret.sh" "$vault" airflow-oauth-client-secret "$secret_file"

cat <<OUT
Add these non-secret values to aks-gitops-deployment/environments/${env}/infrastructure.yaml:
  sso:
    argocdClientId: ${argocd_app}
    airflowClientId: ${airflow_app}
Rotate the Airflow client secret before it expires (1 year): re-run this script.
OUT
