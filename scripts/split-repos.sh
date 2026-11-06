#!/usr/bin/env bash
# Splits this monorepo into the three GitHub repositories the design requires,
# preserving history for each directory.
#   ./scripts/split-repos.sh <github-org>
# Prerequisite: empty repositories <org>/aks-infrastructure-iac,
# <org>/aks-microservices-app and <org>/aks-gitops-deployment exist.
set -euo pipefail
org="${1:?github org}"
cd "$(dirname "$0")/.."
for repo in aks-infrastructure-iac aks-microservices-app aks-gitops-deployment; do
  git subtree split --prefix="$repo" -b "split/$repo"
  git push "git@github.com:${org}/${repo}.git" "split/$repo:main"
  git branch -D "split/$repo"
done
# Replace the placeholders once the repositories exist:
#   grep -rl REPLACE_ORG aks-* | xargs sed -i "s/REPLACE_ORG/${org}/g"
