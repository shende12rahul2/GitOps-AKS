#!/usr/bin/env bash
# Analyses a `terraform show -json` plan.
#   report  : prints GitHub outputs summary=<markdown> and destroys=<n>
#   enforce : exits non-zero when the plan deletes or replaces resources and
#             --allow-destroy is not true, or when it deletes a protected
#             (stateful) resource type without --confirm <env>/<layer>.
set -euo pipefail
plan="$1"; env="$2"; mode="$3"; shift 3
allow_destroy="false"; confirm=""; expected=""
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-destroy) allow_destroy="$2"; shift 2 ;;
    --confirm) confirm="$2"; shift 2 ;;
    --expected) expected="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done

protected='["azurerm_postgresql_flexible_server","azurerm_managed_redis","azurerm_storage_account","azurerm_storage_share","azurerm_key_vault","azurerm_container_registry","azurerm_kubernetes_cluster","azurerm_virtual_network","azurerm_private_dns_zone"]'

count() { jq --arg a "$1" '[.resource_changes[]? | select(.change.actions | index($a))] | length' "$plan"; }
adds=$(count create); changes=$(count update); deletes=$(count delete)
protected_deletes=$(jq -r --argjson p "$protected" '[.resource_changes[]? | select((.change.actions | index("delete")) and (.type as $t | $p | index($t)))] | map(.address) | join(", ")' "$plan")

summary="**${adds}** to add, **${changes}** to change, **${deletes}** to destroy (environment \`${env}\`)."

if [ "$mode" = "report" ]; then
  echo "summary=${summary}"
  echo "destroys=${deletes}"
  exit 0
fi

echo "### Plan guard"
echo "$summary"
if [ "$deletes" -gt 0 ]; then
  jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | "- `\(.address)` (\(.change.actions | join("/")))"' "$plan"
  if [ "$allow_destroy" != "true" ]; then
    echo "::error::Plan destroys ${deletes} resource(s). Re-run with allow_destroy=true after review."
    exit 1
  fi
  if [ -n "$protected_deletes" ] && [ "$confirm" != "$expected" ]; then
    echo "::error::Plan deletes protected stateful resources (${protected_deletes}). Set confirm_protected_destroy to '${expected}' to proceed."
    exit 1
  fi
fi
echo "Plan guard passed."
