#!/usr/bin/env bash
# Prints GitHub Actions outputs `matrix` and `any` listing the Terraform roots
# affected by the diff against the given base ref. A module change affects every
# root; an environment change affects only that environment/layer.
set -euo pipefail
base="${1:-origin/main}"
changed=$(git diff --name-only "$base"...HEAD)

roots=()
if grep -q '^modules/' <<<"$changed"; then
  for env in dev test prod; do for layer in foundation platform data; do roots+=("$env/$layer"); done; done
else
  while read -r path; do
    if [[ "$path" =~ ^environments/(dev|test|prod)/(foundation|platform|data)/ ]]; then
      roots+=("${BASH_REMATCH[1]}/${BASH_REMATCH[2]}")
    fi
  done <<<"$changed"
fi

if [ "${#roots[@]}" -eq 0 ]; then
  echo 'matrix={"include":[]}'
  echo "any=false"
  exit 0
fi

json=$(printf '%s\n' "${roots[@]}" | sort -u | awk -F/ '{printf "%s{\"environment\":\"%s\",\"layer\":\"%s\"}", (NR>1?",":""), $1, $2}')
echo "matrix={\"include\":[${json}]}"
echo "any=true"
