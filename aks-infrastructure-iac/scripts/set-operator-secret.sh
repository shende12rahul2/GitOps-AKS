#!/usr/bin/env bash
# Sets the value of an operator-managed Key Vault secret (placeholders created
# by the data layer) without exposing it on the command line or in shell history.
#
# The vault has no public endpoint, so the default path writes through the
# Azure Resource Manager control plane (works from anywhere for a caller with
# Key Vault Secrets Officer / Contributor). Use --data-plane from the jumpbox.
#
# Usage: ./scripts/set-operator-secret.sh <vault-name> <secret-name> <file> [--data-plane]
set -euo pipefail
vault="${1:?vault name}"; name="${2:?secret name}"; file="${3:?file containing the value}"; mode="${4:-}"
[ -f "$file" ] || { echo "value file not found: $file" >&2; exit 1; }

if [ "$mode" = "--data-plane" ]; then
  az keyvault secret set --vault-name "$vault" --name "$name" --file "$file" --output none
else
  id=$(az keyvault show --name "$vault" --query id -o tsv)
  body=$(mktemp); trap 'rm -f "$body"' EXIT
  python3 - "$file" > "$body" <<'PY'
import json, sys
print(json.dumps({"properties": {"value": open(sys.argv[1]).read()}}))
PY
  az rest --method put --url "https://management.azure.com${id}/secrets/${name}?api-version=2023-07-01" --body "@${body}" --output none
fi
echo "secret ${name} updated in ${vault}"
