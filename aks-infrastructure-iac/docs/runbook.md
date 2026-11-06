# Deployment runbook (empty subscription -> working POC)

Conventions: `ENV=dev`, region `eastus2`, project `akspoc`, GitHub org `$ORG`.
Commands run from a workstation with Azure CLI >= 2.70, Terraform >= 1.11
(tested 1.17.1), Helm 3, kubectl + kubelogin, `gh`, `jq`, `yq`.

---

## Phase 1 - Prerequisites

**Design**: one subscription, three environments, three repositories; Entra
groups and app registrations created by an Entra administrator (CI has no Graph
permissions); a single region that offers every service.

1. Permissions: subscription **Owner** (bootstrap only), Entra **Groups
   Administrator** + **Application Administrator** (one-time).
2. Region check:
   ```bash
   az account set -s <subscription-id>
   az aks get-versions -l eastus2 -o table            # 1.36 must be listed
   az vm list-skus -l eastus2 --size Standard_D4ads_v5 --query "[].restrictions" -o tsv   # empty = available
   az provider show -n Microsoft.Cache --query "resourceTypes[?resourceType=='redisEnterprise'].locations" -o tsv | grep -i "east us 2"
   ```
3. Resource providers and features (idempotent):
   ```bash
   aks-infrastructure-iac/scripts/register-providers.sh <subscription-id>
   ```
4. Repositories: create `aks-infrastructure-iac`, `aks-microservices-app`,
   `aks-gitops-deployment` (private) and push each directory of this monorepo
   (see the root README for `git subtree split`).
5. Persona groups:
   ```bash
   aks-infrastructure-iac/bootstrap/entra/create-groups.sh akspoc   # prints entra_group_object_ids
   ```
6. Naming/tagging: `modules/naming` (`<abbr>-akspoc-<env>-eus2[-purpose]`,
   tags `project, environment, owner, cost_center, managed_by, repository, layer`).
7. CIDRs: dev 10.10.0.0/16, test 10.20.0.0/16, prod 10.30.0.0/16 (no overlap
   with on-premises or other spokes).

**Expected**: providers `Registered`, `EnableApplicationGatewayNetworkIsolation`
and `EncryptionAtHost` `Registered`, five groups exist.
**Cost/security**: none yet. Group membership is the root of all access.

## Phase 2 - Terraform backend

```bash
cd aks-infrastructure-iac/bootstrap/terraform-backend
cp terraform.tfvars.example terraform.tfvars   # subscription, GitHub org, platform admins group
terraform init && terraform apply
terraform output                               # storage_account_name, github_identities, tenant_id
# migrate the bootstrap's own state into the new account
cp backend.hcl.example backend.hcl && sed -i "s/<output storage_account_name>/$(terraform output -raw storage_account_name)/" backend.hcl
cat >> versions.tf <<'HCL'
terraform { backend "azurerm" {} }
HCL
terraform init -migrate-state -backend-config=backend.hcl && rm -f terraform.tfstate*
```

Then put the account name into every `environments/*/*/backend.hcl` and
`*.tfvars` (`REPLACE_WITH_STATE_ACCOUNT`), and configure GitHub (see
[terraform.md](terraform.md#cicd)): variables `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID_<ENV>`, `AZURE_CLIENT_ID_PLAN_<ENV>`; environments `dev`,
`test`, `prod` with `AZURE_CLIENT_ID` (apply identity) and reviewers on test/prod.

**Validate**: `az storage blob list --account-name <st> -c tfstate-bootstrap --auth-mode login -o table` shows `bootstrap.tfstate`;
`az storage account show -n <st> --query "{keys:allowSharedKeyAccess, versioning:...}"`;
a PR to the infra repo runs `terraform-plan` successfully with OIDC.
**Security**: no keys, per-environment containers, delete lock, versioning + PITR.

## Phase 3 - Foundation

```bash
cd aks-infrastructure-iac/environments/dev/foundation
export TF_VAR_subscription_id=<subscription-id>
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
```

(Normal path: merge the PR; `terraform-apply` runs dev automatically.)

**Expected**: `rg-akspoc-dev-eus2-network`, VNet with 5 subnets, 5 NSGs, 5-6
private DNS zones linked to the VNet. **Validate**: `terraform output subnet_cidrs`;
`az network vnet subnet list -g rg-akspoc-dev-eus2-network --vnet-name vnet-akspoc-dev-eus2 -o table`.
**Cost**: ~0 (DNS zones cents/month; NAT only in prod).

## Phase 4 - AKS platform

Fill `environments/dev/platform/terraform.tfvars` (group IDs, GitHub org), then:

```bash
cd ../platform && terraform init -backend-config=backend.hcl && terraform apply
```

Creates Log Analytics + Azure Monitor workspace + action group, identities
(control plane, kubelet, 7 workload identities with federated credentials,
GitHub ACR identity), ACR, Key Vault (+PE), App Gateway WAF_v2 (private
frontend 10.10.4.10), private AKS with AGIC, CSI drivers, Container Insights and
managed Prometheus, persona RBAC, `app/argocd/airflow.poc.example.com` A records.

**Validate**:
```bash
az aks show -g rg-akspoc-dev-eus2-platform -n aks-akspoc-dev-eus2 --query "{k8s:currentKubernetesVersion, private:apiServerAccessProfile.enablePrivateCluster, aad:aadProfile.enableAzureRbac, oidc:oidcIssuerProfile.enabled, wi:securityProfile.workloadIdentity.enabled}"
az aks command invoke -g rg-akspoc-dev-eus2-platform -n aks-akspoc-dev-eus2 --command "kubectl get nodes -L workload-class"
```
Expected: 1 system + 2 `apps` nodes `Ready`.
**Cost**: the App Gateway and nodes start billing here (largest items).
**Limitations**: Free tier (no API SLA), single zone.

## Phase 5 - Managed data services

```bash
cd ../data && terraform init -backend-config=backend.hcl && terraform apply
```

PostgreSQL 17 (B2s, VNet integration, Entra admins), Managed Redis
(Balanced_B0, NoCluster, NoEviction, PE), Storage (keys disabled, SMB OAuth,
PE) with shares `shared-files` + `airflow-logs`, Key Vault secrets (8
Terraform-managed, 3 operator placeholders) with per-secret RBAC.

Set the operator secrets:
```bash
ssh-keygen -t ed25519 -N '' -f gitsync -C airflow-gitsync-dev
gh repo deploy-key add gitsync.pub --repo $ORG/aks-microservices-app --title airflow-gitsync-dev
scripts/set-operator-secret.sh <kv> airflow-gitsync-ssh-key gitsync
ssh-keygen -t ed25519 -N '' -f gitops -C argocd-dev                       # only if the GitOps repo is private
gh repo deploy-key add gitops.pub --repo $ORG/aks-gitops-deployment --title argocd-dev
scripts/set-operator-secret.sh <kv> argocd-repo-ssh-key gitops
shred -u gitsync gitsync.pub gitops gitops.pub
bootstrap/entra/create-app-registrations.sh dev "$(cd ../platform && terraform output -raw aks_oidc_issuer_url)" poc.example.com <kv> akspoc
```

**Validate**: `az postgres flexible-server show ... --query network`,
`az redisenterprise show ... --query publicNetworkAccess` (Disabled),
`az storage account show -n <st> --query "{keys:allowSharedKeyAccess, public:publicNetworkAccess}"` (false/Disabled),
`az keyvault secret list --vault-name <kv> --query "[].name"` (from the jumpbox).
**Note**: application databases do not exist yet (created in Phase 7).

## Phase 6 - GitOps bootstrap

1. Generate the environment contract and commit it to the GitOps repo (PR):
   ```bash
   aks-infrastructure-iac/scripts/export-gitops-values.sh dev <argocd-client-id> <airflow-client-id> \
     > aks-gitops-deployment/environments/dev/infrastructure.yaml
   ```
   Also replace `REPLACE_ORG` (repo URLs) and the placeholder IDs in
   `environments/dev/argocd-values.yaml` (tenant, Argo CD client ID, group IDs).
2. Install Argo CD and the root app (private cluster: through ARM):
   ```bash
   aks-gitops-deployment/argocd/bootstrap/install.sh dev rg-akspoc-dev-eus2-platform aks-akspoc-dev-eus2 --invoke
   ```
3. Argo CD now syncs, in waves: projects -> namespaces -> policies/RBAC/NetworkPolicies
   -> cert-manager -> storage + secrets -> db-bootstrap -> ingress + monitoring -> Airflow + apps.

**Validate**:
```bash
az aks command invoke -g rg-akspoc-dev-eus2-platform -n aks-akspoc-dev-eus2 --command "kubectl -n argocd get applications"
```
From the jumpbox: `https://argocd.poc.example.com` -> "Log in via Microsoft Entra ID"
(trust the POC CA first, see Phase 9). `argocd login argocd.poc.example.com --sso --grpc-web`.
**Security**: local admin disabled, SSO with workload identity (no client secret), RBAC by group.

## Phase 7 - Platform workloads

Delivered by Argo CD (no manual steps): static PV/PVC for both shares,
NetworkPolicies, `airflow-kv-sync` (Key Vault -> Kubernetes secrets),
`db-bootstrap` Job, Airflow with external PostgreSQL/Redis and Git-Sync.

**Validate**:
```bash
kubectl get pv,pvc -A | grep -E 'shared-files|airflow-logs'          # Bound
kubectl -n platform-jobs logs job/db-bootstrap                       # {"status": "ok", "created_databases": [...]}
kubectl -n airflow get secrets | grep airflow-                       # 9 synced secrets
kubectl -n airflow get pods                                          # api-server, scheduler, dag-processor, triggerer, worker Running
kubectl -n airflow logs deploy/airflow-dag-processor -c git-sync --tail=5
```

## Phase 8 - Application build

1. GitHub (app repo): variables `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID_DEV`,
   `AZURE_CLIENT_ID_ACR_DEV` (platform output `github_acr_identity_client_id`),
   `ACR_NAME_DEV`, `GITOPS_APP_ID`; secret `GITOPS_APP_PRIVATE_KEY` (GitHub App
   with contents + pull-requests write on the GitOps repo only); environments
   `test`/`prod` with `AZURE_CLIENT_ID_ACR`, `ACR_NAME`, `AZURE_SUBSCRIPTION_ID`.
2. Branch protection on `main`: `test`, `security-scan`, `validate-dags` required.
3. Merge to `main` (or run `build.yml` with `images=all`): images are built,
   scanned, pushed by digest, and a `deploy(dev)` PR opens in the GitOps repo.

**Validate**: `az acr repository list -n <acr>`; `az acr manifest list-metadata -r <acr> -n user-service`.

## Phase 9 - GitOps deployment

Merge the `deploy(dev)` PR. The `microservices` ApplicationSet syncs the five
charts (migration Jobs, then Deployments); `platform-ingress` publishes the
routes through AGIC; cert-manager issues `app-tls`, `argocd-tls`, `airflow-tls`.

Trust the POC CA on the client (jumpbox):
```bash
kubectl -n cert-manager get secret poc-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > poc-ca.crt
sudo cp poc-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
```

**Validate**:
```bash
kubectl -n apps get deploy,pods -o wide
kubectl -n apps get ingress apps
az network application-gateway show-backend-health -g rg-akspoc-dev-eus2-platform -n agw-akspoc-dev-eus2 -o table
aks-gitops-deployment/scripts/validate-shared-storage.sh dev
```

## Phase 10 - Functional validation

| # | Test | Command / action | Expected |
|---|---|---|---|
| 1 | Frontend over HTTPS | browser `https://app.poc.example.com` | dashboard with users, products, orders, notifications |
| 2 | All 5 APIs | `scripts/smoke-test.sh https://app.poc.example.com poc-ca.crt` | 200s, 301 on HTTP, HSTS |
| 3 | PostgreSQL CRUD | create order in UI; `curl -X PUT .../api/users/1` with key | persisted |
| 4 | Redis caching | 2nd `GET /api/products/1` -> `X-Cache: HIT`; PUT -> `MISS` | |
| 5 | Airflow DAGs | trigger `order_processing_pipeline` | all tasks green; notifications verified |
| 6 | DAG update from GitHub | PR bumping `DAG_VERSION` in `dag_sync_canary.py` | new version in UI within ~60 s |
| 7 | Drift detection | `kubectl -n apps scale deploy user-service --replicas=3` | reverted (dev self-heal) |
| 8 | Git rollback | revert last `deploy(dev)` PR | previous digest running |
| 9 | Multi-user RBAC | `scripts/test-rbac.sh dev ...` + persona sign-ins | matches [rbac-matrix.md](rbac-matrix.md) |
| 10 | Rescheduling | `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` | pods move, still healthy |
| 11 | Shared file persistence | `validate-shared-storage.sh dev` | PASS (9 steps) |
| 12 | Backend isolation | `kubectl -n apps run t --rm -it --image=<acr>/frontend@<digest> -- python -c "import urllib.request;urllib.request.urlopen('http://notification-service:8000/healthz/ready')"` from a non-allowed label | timeout |

## Phase 11 - Operations

- **Monitoring**: [monitoring.md](monitoring.md). Container Insights workbooks, Prometheus alerts, KQL.
- **Backup/restore**: [backup-dr.md](backup-dr.md). Quarterly PostgreSQL restore test.
- **Security verification**: [security.md](security.md) checklist.
- **Terraform drift**: scheduled `terraform plan -detailed-exitcode` (exit 2 = drift) on main; investigate any manual change and either import it or let Terraform revert it.
- **AKS upgrades**: patch channel + NodeImage auto-upgrade in the Sunday window. Minor upgrades: bump `kubernetes_version` in dev -> soak -> test -> prod; check `az aks get-upgrades`, deprecated APIs (`kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis`), PDBs, surge capacity.
- **Cost**: [cost-estimation.md](cost-estimation.md); `az aks stop` out of hours in dev.
- **DR**: [backup-dr.md](backup-dr.md).
- **Production migration**: [aks-sizing.md](aks-sizing.md#single-zone-poc-vs-production-ha), prod tfvars, hub-and-spoke with Azure Firewall, Front Door for internet ingress, self-hosted runners in the VNet, image signing.
