#!/usr/bin/env bash
# Fails when the Terraform root code differs between dev, test and prod.
# Environments may differ only in terraform.tfvars and backend.hcl, so a
# change promoted to prod is exactly the change that was tested in dev.
set -euo pipefail
cd "$(dirname "$0")/../environments"
status=0
for layer in foundation platform data; do
  for env in test prod; do
    for f in dev/"$layer"/*.tf; do
      name=$(basename "$f")
      if ! cmp -s "$f" "$env/$layer/$name"; then
        echo "::error::environments/$env/$layer/$name differs from dev (only *.tfvars and backend.hcl may differ)"
        status=1
      fi
    done
    extra=$(comm -13 <(ls dev/"$layer"/*.tf | xargs -n1 basename | sort) <(ls "$env/$layer"/*.tf | xargs -n1 basename | sort))
    if [ -n "$extra" ]; then
      echo "::error::environments/$env/$layer has extra files: $extra"; status=1
    fi
  done
done
[ "$status" -eq 0 ] && echo "environment parity OK"
exit "$status"
