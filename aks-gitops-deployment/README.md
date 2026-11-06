# aks-gitops-deployment

Desired state of every Kubernetes resource, reconciled **only** by Argo CD.
Merging a pull request here is a deployment; reverting it is a rollback.

## Layout

```
helm/<service>/                 five independent charts (digest-pinned images, workload identity, KV CSI,
                                RWX shared volume, probes, HPA, PDB, NetworkPolicy, migration hook, helm test, schema)
platform/airflow/               values for the official Airflow chart 1.22.0 (CeleryExecutor, external PG/Redis, Git-Sync, Entra SSO)
platform/ingress/               central Ingress (AGIC or Traefik), cert-manager issuers/certificates, Traefik values
platform/secrets/               Key Vault -> Kubernetes Secrets for Airflow (CSI + workload identity)
platform/database/              db-bootstrap Job (databases, Entra roles, grants)
platform/monitoring/            managed Prometheus scrape settings
kubernetes/namespaces/          namespaces with Pod Security Standards, quotas, limit ranges
kubernetes/rbac/                Kubernetes RBAC for Entra groups (complements Azure RBAC)
kubernetes/network-policies/    default deny + explicit allows (Cilium)
kubernetes/storage/             static Azure Files PV/PVC (Terraform-owned shares, managed-identity mount)
kubernetes/security-policies/   ValidatingAdmissionPolicy: images from the ACR, pinned by digest
argocd/bootstrap/               one-time install (works through `az aks command invoke`), base values, root app
argocd/projects/                AppProjects platform / apps / airflow
argocd/applications/            app-of-apps with sync waves
argocd/applicationsets/         microservices ApplicationSet
environments/<env>/             infrastructure.yaml (generated contract), apps/*.yaml (digests), platform/*.yaml, argocd*.yaml
scripts/                        render.py (Argo CD-faithful rendering), validate-shared-storage, smoke-test, test-rbac
tests/policies/                 admission policy tests (kind)
```

## Values layering

1. chart `values.yaml`
2. `environments/<env>/infrastructure.yaml` - generated from Terraform outputs (`global.*`: tenant, Key Vault, identities, endpoints, CIDRs). Non-secret.
3. `environments/<env>/apps/<svc>.yaml` / `platform/*.yaml` - reviewed per-environment settings; `image.digest` written by CI PRs.

## Validate locally

```bash
python3 scripts/render.py dev --out /tmp/rendered --chart-cache ./.chart-cache   # see .github/workflows/validate.yml for pulling remote charts
kubeconform -strict -summary -kubernetes-version 1.36.0 -skip CustomResourceDefinition \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /tmp/rendered/*.yaml
for c in helm/*; do helm lint $c -f $c/ci/test-values.yaml --strict; done
```

## Environments

| | dev | test | prod |
|---|---|---|---|
| Sync | automated, prune, self-heal | automated, self-heal | manual, sync window weekdays 08-18 UTC |
| Replicas / HPA | 1 / off | 1 / off | 2 / on, zone spread |
| Admission policy | Warn | Deny | Deny |
| Developer Argo CD sync | yes (apps) | no | no |
| DB read-only groups | QA, developers | QA | none |

Bootstrap and day-2 procedures: [runbook](../aks-infrastructure-iac/docs/runbook.md),
design: [CI/CD and GitOps](../aks-infrastructure-iac/docs/gitops-cicd.md).
