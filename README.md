# Azure AKS Enterprise POC: Terraform, Microservices, Airflow, GitOps

A complete, secure and cost-conscious AKS proof of concept, built as **three
independent repositories** (kept in this monorepo for review; split them with
`scripts/split-repos.sh <org>`):

| Repository | Purpose | Deploys to |
|---|---|---|
| [`aks-infrastructure-iac`](aks-infrastructure-iac/) | Modular Terraform (19 modules, 3 state layers x 3 environments), GitHub OIDC pipelines, **all architecture docs and the runbook** | Azure (ARM) |
| [`aks-microservices-app`](aks-microservices-app/) | 5 FastAPI services, Airflow image + DAGs, db-bootstrap tool, CI (test, scan, build, GitOps PR) | ACR only |
| [`aks-gitops-deployment`](aks-gitops-deployment/) | 5 Helm charts, Argo CD app-of-apps, Airflow values, ingress, policies, storage, per-environment values | AKS (Argo CD pull) |

## What is in the box

- **Private AKS 1.36** (Entra ID + Azure RBAC, local accounts off, Azure CNI
  Overlay + Cilium, workload identity, Key Vault CSI, Azure Files CSI, system +
  user pools, Container Insights + managed Prometheus, Deployment Safeguards).
- **Centralised HTTPS entry point**: Application Gateway **WAF_v2 + AGIC** on a
  private frontend (public WAF frontend optional), or a low-cost **internal
  Traefik** mode, one switch each in Terraform and GitOps (never both). Separate private
  hostnames for Argo CD and Airflow with Entra SSO.
- **Managed data services, private only**: PostgreSQL Flexible (VNet
  integration, Entra auth, passwordless apps, versioned SQL bootstrap), **Azure
  Managed Redis** (NoCluster + NoEviction for a Celery-compatible shared broker,
  Entra auth for apps), **Azure Files** (SMB, managed-identity mount, no storage
  keys, static PVs, cross-node tested).
- **Airflow 3.2.2** (official chart 1.22.0, CeleryExecutor on Managed Redis,
  metadata on PostgreSQL, Git-Sync from GitHub, Entra SSO with app roles).
- **GitOps**: CI publishes digest-pinned, scanned images with SBOM/provenance and
  opens GitOps PRs; Argo CD syncs in waves; promotion copies digests; rollback =
  revert.
- **Security**: Key Vault with per-secret RBAC, no secrets in Git or Kubernetes
  Secrets for apps, PSS restricted, default-deny NetworkPolicies, admission
  policy (ACR + digest only), WAF, TLS everywhere, OIDC for CI, destroy guards.

## Start here

1. [Architecture](aks-infrastructure-iac/docs/architecture.md): diagrams for every traffic flow.
2. [Runbook](aks-infrastructure-iac/docs/runbook.md): Phases 1-11 from an empty subscription.
3. [Validation report](aks-infrastructure-iac/docs/validation-report.md): what was executed while building this, and what still needs Azure.
4. [RBAC matrix](aks-infrastructure-iac/docs/rbac-matrix.md), [security](aks-infrastructure-iac/docs/security.md), [cost](aks-infrastructure-iac/docs/cost-estimation.md), [sizing](aks-infrastructure-iac/docs/aks-sizing.md), [backup/DR](aks-infrastructure-iac/docs/backup-dr.md), [troubleshooting](aks-infrastructure-iac/docs/troubleshooting.md).

## Before first use

- Replace `REPLACE_ORG` (GitHub org) and `REPLACE_WITH_STATE_ACCOUNT` placeholders.
- Group/client IDs in `aks-gitops-deployment/environments/*/infrastructure.yaml`
  are placeholders until `scripts/export-gitops-values.sh` generates the file.
- `poc.example.com` is a sample private DNS zone; set `app_dns_zone_name`.

Run every offline check: `scripts/validate-all.sh`.
