# RBAC matrix

Personas are Entra ID security groups (`bootstrap/entra/create-groups.sh`):
`grp-akspoc-platform-admins`, `-devops`, `-developers`, `-qa`, `-readers`.
Workloads use their own managed identities (never personas).

Legend: **F** full, **W** write/operate, **R** read, **—** none.

| Resource / action | Platform Admin | DevOps | Developer | QA | Read-Only |
|---|---|---|---|---|---|
| Subscription | Owner (out of band) | — | — | — | — |
| Resource groups (network/platform/data) | F | R | R (platform) | R (platform) | R |
| Infrastructure changes | merge + approve prod apply | PRs + apply dev/test | PRs only | — | — |
| AKS cluster (Azure RBAC) | Cluster Admin | Reader (cluster) | — | — | Reader (cluster) |
| Namespace `apps` | F | R + restart/scale/delete pods/run Jobs (K8s role) | R + pod logs | R + pod logs | R |
| Namespace `airflow` | F | R + operate | R + pod logs | R + pod logs | R |
| Kubernetes Secrets | R/W | — | — | — | — |
| `kubectl exec` / port-forward | yes | — | port-forward in dev only | — | — |
| Application deployments | via Git (+ break-glass kubectl) | via Git (approve test) | via Git PR | — | — |
| Pod logs | yes | yes | yes (apps, airflow) | yes (apps, airflow) | yes (Log Analytics) |
| Log Analytics / metrics | F | Reader | Reader | Reader | Reader |
| ACR | F | AcrPull | AcrPull | — | — |
| ACR push | CI identity only (AcrPush) | — | — | — | — |
| Key Vault secret values | Secrets Officer | Secrets Officer | — | — | metadata only (Key Vault Reader) |
| Workload secret access | per-secret Secrets User to each workload identity | | | | |
| Redis configuration | via Terraform | R (portal) | Monitoring Reader | — | R |
| Redis data | product/order identities (Entra policy), Airflow (key) | — | — | — | — |
| PostgreSQL administration | Entra admin (group) | — | — | — | — |
| PostgreSQL app data | service identities (own DB only) | — | read-only role (dev/test) | read-only role (dev/test) | — |
| Azure Files | via Terraform | Storage File Data Privileged Reader | — | Storage File Data Privileged Reader | — |
| Argo CD | `role:platform-admin` | sync/override/actions, no delete | view apps/airflow, logs; **sync apps in dev** | view apps/airflow, logs | `role:readonly` |
| Airflow | Admin | Op | User (trigger DAGs) | User | Viewer |
| GitHub `aks-infrastructure-iac` | admin | maintain | read / PR | read | read |
| GitHub `aks-microservices-app` | admin | maintain | write (PR, no direct push to main) | triage | read |
| GitHub `aks-gitops-deployment` | admin | maintain (approve dev/test) | PR to `environments/dev/apps` | approve test | read |
| Terraform pipelines | approve prod environment | run test, approve test | — | — | — |

Where it is implemented:

- Azure RBAC: `environments/<env>/platform/rbac.tf`, `environments/<env>/data/rbac.tf`, per-secret RBAC in `data/secrets.tf`.
- Kubernetes RBAC: `aks-gitops-deployment/kubernetes/rbac` (log-reader, workload-operator, port-forward).
- Argo CD: `configs.rbac` in `environments/<env>/argocd-values.yaml`; AppProject roles.
- Airflow: Entra app roles `Airflow.Admin/Op/User/Viewer` mapped by `AUTH_ROLES_MAPPING`.
- PostgreSQL: `db-bootstrap` (`<db>_readonly` granted to groups in `readerGroups`).
- GitHub: CODEOWNERS, branch protection, environments (see repository READMEs).

The built-in **AKS RBAC Writer** role is deliberately not used for people: it can
read Secrets and run pods as any service account.

## Testing permissions

```bash
# As a platform admin: role assignments per group + impersonated Kubernetes RBAC
aks-gitops-deployment/scripts/test-rbac.sh dev rg-akspoc-dev-eus2-platform aks-akspoc-dev-eus2

# As a persona member (sign in as that user)
az login && az aks get-credentials -g rg-akspoc-dev-eus2-platform -n aks-akspoc-dev-eus2 && kubelogin convert-kubeconfig -l azurecli
kubectl auth can-i --list -n apps
kubectl auth can-i get secrets -n apps            # developers/qa/devops: no
kubectl auth can-i get pods/log -n apps           # developers/qa: yes
kubectl auth can-i patch deployments -n apps      # devops: yes, developers: no
argocd login argocd.poc.example.com --sso --grpc-web && argocd account can-i sync applications 'apps/*'
az keyvault secret show --vault-name <kv> -n internal-api-key   # developers: Forbidden
```
