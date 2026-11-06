# Troubleshooting

Private cluster: run `kubectl` from the jumpbox, or prefix with
`az aks command invoke -g <rg> -n <aks> --command "<kubectl ...>"`.

## Access

| Symptom | Commands |
|---|---|
| `kubectl` hangs / `no such host` | `nslookup <private-fqdn>` (must resolve inside the VNet); use `az aks command invoke` |
| `Forbidden` for a persona | `az role assignment list --assignee <group-id> --all -o table`; `kubectl auth can-i --list -n apps`; `kubelogin convert-kubeconfig -l azurecli` |
| Argo CD SSO loop / 401 | `kubectl -n argocd logs deploy/argocd-server | grep -i oidc`; federated credential subject `system:serviceaccount:argocd:argocd-server`; issuer = AKS OIDC URL; groups claim `ApplicationGroup` |
| Airflow login fails | api-server logs; redirect URI `https://airflow.<zone>/auth/oauth-authorized/azure`; user has an app role |

## Workload identity

```bash
kubectl -n apps get sa user-service -o yaml | grep azure.workload.identity
kubectl -n apps get pod -l app.kubernetes.io/name=user-service -o yaml | grep -E 'AZURE_(CLIENT_ID|FEDERATED_TOKEN_FILE)'
az identity federated-credential list --identity-name id-akspoc-dev-eus2-user-service -g rg-akspoc-dev-eus2-platform -o table
```
`AADSTS70021` = subject/issuer mismatch; `AADSTS700016` = wrong client ID.

## Key Vault CSI

```bash
kubectl -n apps describe pod <pod> | grep -A5 -i "MountVolume"
kubectl -n kube-system logs -l app=secrets-store-provider-azure --tail=50
kubectl -n airflow get secretproviderclass airflow-kv -o yaml
```
`403` = missing secret-scoped role (`data/secrets.tf` readers); `PLACEHOLDER-set-by-operator` = operator secret not set.

## PostgreSQL

```bash
kubectl -n platform-jobs logs job/db-bootstrap
kubectl -n apps logs job/user-service-migrate
kubectl -n apps exec deploy/user-service -- python -c "import socket;print(socket.gethostbyname('<server-fqdn>'))"   # 10.10.6.x
```
`password authentication failed for user "id-..."` = role not created by db-bootstrap or token for the wrong identity.
`no pg_hba.conf entry` = password auth disabled or wrong user. `too many connections` = lower pool sizes / enable PgBouncer (GP tier).

## Redis

```bash
kubectl -n apps exec deploy/product-service -- python -c "from app.main import Settings; from svc_common.cache import build_client; print(build_client(Settings()).ping())"
kubectl -n airflow exec deploy/airflow-worker -c worker -- celery --app airflow.providers.celery.executors.celery_executor.app inspect ping
```
`OOM command not allowed` = NoEviction instance full (check `usedmemorypercentage`, scale SKU, check cache TTLs). `WRONGPASS` = broker URL key rotated: re-apply data layer, wait for CSI rotation, restart Airflow.

## Azure Files

```bash
kubectl describe pvc -n apps shared-files-pvc
kubectl -n kube-system logs -l app=csi-azurefile-node -c azurefile --tail=100 | grep -i -E "error|mount"
az role assignment list --scope <storage-account-id> -o table      # Storage File Data SMB MI Admin for kubelet identity
az storage account show -n <st> --query "{oauth:azureFilesIdentityBasedAuthentication, keys:allowSharedKeyAccess}"
```
`Permission denied` on mount = SMB OAuth not enabled or role missing; `Host is down` = private DNS/PE or NSG port 445.

## Ingress / App Gateway

```bash
kubectl -n kube-system logs deploy/ingress-appgw-deployment --tail=100
az network application-gateway show-backend-health -g <rg> -n <agw> -o table
kubectl -n apps describe ingress apps
kubectl -n apps get certificate,certificaterequest
```
502 = unhealthy backends (readiness probe, NetworkPolicy allowing the App Gateway subnet); AGIC errors about permissions = AGIC identity roles (`agic-*` in platform main.tf).

## Argo CD

```bash
argocd app list; argocd app get <app> --show-operation; argocd app diff <app>
kubectl -n argocd logs deploy/argocd-repo-server --tail=50       # value file / chart errors
kubectl -n argocd logs statefulset/argocd-application-controller --tail=50
```
`app path does not exist` = repoURL/targetRevision; `ComparisonError ... valueFiles` = relative path; admission denied = image not digest-pinned or not from the ACR.

## Airflow

```bash
kubectl -n airflow logs deploy/airflow-scheduler -c scheduler --tail=50
kubectl -n airflow exec deploy/airflow-dag-processor -c dag-processor -- airflow dags list-import-errors
kubectl -n airflow logs deploy/airflow-worker -c worker --tail=50
kubectl -n airflow logs job/airflow-run-airflow-migrations
```
Tasks stuck in `queued` = broker connectivity (Redis TLS/key), worker not running, or `ssl_mutual_tls` left True.

## Terraform

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform force-unlock <lock-id>         # only if no run is active
terraform plan -refresh-only             # inspect drift
terraform state list | grep <name>; terraform state show <address>
```
