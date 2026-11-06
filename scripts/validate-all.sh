#!/usr/bin/env bash
# Runs every offline check across the three repositories (what CI runs, minus
# anything that needs Azure, GitHub or Docker). Tools: terraform, tflint, helm,
# kubeconform, python3 with the packages from the Makefile, optionally checkov.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
step() { printf '\n== %s\n' "$*"; }

step "Terraform: fmt, parity, validate, mocked tests"
cd "$root/aks-infrastructure-iac"
terraform fmt -check -recursive
scripts/check-env-parity.sh
for d in bootstrap/terraform-backend environments/*/*; do
  (cd "$d" && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color >/dev/null && echo "valid: $d")
  if [ -d "$d/tests" ]; then (cd "$d" && terraform test -no-color | tail -1); fi
done
tflint --recursive --format=compact || true
command -v checkov >/dev/null && checkov -d . --config-file .checkov.yaml --compact --quiet || echo "checkov not installed (skipped)"

step "Application: lint + unit tests"
cd "$root/aks-microservices-app"
ruff check . && ruff format --check .
(cd libs/svc-common && python -m pytest -q tests)
for s in frontend user-service product-service order-service notification-service; do
  (cd "services/$s" && REDIS_ENABLED=false python -m pytest -q tests)
done
(cd tools/db-bootstrap && python -m pytest -q tests)

step "GitOps: helm lint + render + kubeconform"
cd "$root/aks-gitops-deployment"
for c in helm/*; do helm lint "$c" -f "$c/ci/test-values.yaml" --strict >/dev/null && echo "lint ok: $c"; done
for e in dev test prod; do
  python3 scripts/render.py "$e" --out "/tmp/rendered-$e" ${CHART_CACHE:+--chart-cache "$CHART_CACHE"} >/dev/null
  kubeconform -strict -summary -kubernetes-version 1.36.0 -skip CustomResourceDefinition \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    "/tmp/rendered-$e"/*.yaml
done
