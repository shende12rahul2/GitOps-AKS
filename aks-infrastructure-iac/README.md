# aks-infrastructure-iac

Modular Terraform for the Azure AKS enterprise POC: private AKS, Application
Gateway WAF_v2 + AGIC (or internal ingress), ACR, Key Vault, Azure Managed
Redis, PostgreSQL Flexible Server, Azure Files, identities, RBAC and monitoring.

| | |
|---|---|
| Terraform | `>= 1.11.0, < 2.0.0` (tested 1.17.1) |
| AzureRM | `~> 5.13` (tested 5.13.0), lock files for linux/darwin/windows |
| State | Azure Storage, Entra auth, one container per environment, one key per layer |
| CI | GitHub Actions with OIDC (no secrets) |

## Layout

```
bootstrap/terraform-backend   state account + GitHub OIDC identities (run once, local state, then migrated)
bootstrap/entra               persona groups, Argo CD / Airflow SSO app registrations (Entra admin)
modules/                      19 reusable modules (README per module, generated tables)
environments/<env>/foundation network: RGs, VNet, subnets, NSGs, NAT (opt.), private DNS
environments/<env>/platform   monitoring, identities, ACR, Key Vault, App Gateway, AKS, RBAC, DNS records, jumpbox (opt.)
environments/<env>/data       PostgreSQL, Managed Redis, Storage/Azure Files, Key Vault secrets, data RBAC
scripts/                      export-gitops-values, set-operator-secret, register-providers, plan guard, cost estimate
docs/                         architecture, network, Terraform, GitOps, Airflow, database, storage, RBAC, security,
                              monitoring, sizing, cost, runbook, troubleshooting, backup/DR, validation report
```

## Quick start

See [docs/runbook.md](docs/runbook.md) (Phases 1-11). In short:

```bash
scripts/register-providers.sh <subscription-id>
bootstrap/entra/create-groups.sh akspoc
(cd bootstrap/terraform-backend && terraform init && terraform apply)
export TF_VAR_subscription_id=<subscription-id>
for layer in foundation platform data; do
  (cd environments/dev/$layer && terraform init -backend-config=backend.hcl && terraform apply)
done
scripts/export-gitops-values.sh dev > ../aks-gitops-deployment/environments/dev/infrastructure.yaml
```

## Local checks (same as CI)

```bash
terraform fmt -check -recursive
scripts/check-env-parity.sh
for d in environments/*/* bootstrap/terraform-backend; do (cd $d && terraform init -backend=false && terraform validate); done
(cd environments/dev/platform && terraform test)          # mocked provider: plans/applies without Azure
tflint --init && tflint --recursive
checkov -d . --config-file .checkov.yaml
```

## Documentation

[Architecture](docs/architecture.md) - [Network](docs/network-design.md) -
[Terraform](docs/terraform.md) - [CI/CD + GitOps](docs/gitops-cicd.md) -
[Airflow](docs/airflow.md) - [PostgreSQL](docs/database.md) -
[Azure Files](docs/shared-storage.md) - [RBAC matrix](docs/rbac-matrix.md) -
[Security](docs/security.md) - [Monitoring](docs/monitoring.md) -
[Sizing](docs/aks-sizing.md) - [Cost](docs/cost-estimation.md) -
[Runbook](docs/runbook.md) - [Troubleshooting](docs/troubleshooting.md) -
[Backup/DR](docs/backup-dr.md) - [Validation report](docs/validation-report.md)
