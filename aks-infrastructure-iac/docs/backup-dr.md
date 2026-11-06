# Backup, restore and disaster recovery

| Asset | Protection | RPO | Restore |
|---|---|---|---|
| Terraform state | blob versioning, soft delete 30 d, PITR 29 d, RA-GRS, delete lock | minutes | promote previous blob version |
| Git (3 repositories) | GitHub + local clones; everything in Kubernetes is rebuildable from Git | 0 | re-bootstrap Argo CD |
| PostgreSQL | automated backups + WAL, PITR 7 d (dev) / 35 d (prod), geo-redundant (prod) | ~5 min | `az postgres flexible-server restore` / `geo-restore` |
| Managed Redis | cache + broker; optional RDB persistence (`rdb_backup_frequency`) | broker: in-flight tasks | recreate; Airflow re-queues failed tasks (retries) |
| Azure Files | share soft delete 7 d; Azure Backup snapshots (prod) | daily (backup) | `az storage share-rm restore` / backup restore |
| Key Vault | soft delete + purge protection; secrets reproducible by Terraform | 0 | `az keyvault secret recover`; re-apply data layer |
| ACR | images rebuildable from Git tags/commits; geo-replication (Premium) | 0 | rebuild or replicate |
| AKS | stateless (GitOps) | 0 | recreate cluster (Terraform) + `install.sh` |

## Scenarios

**Bad deployment** -> revert the GitOps PR (minutes).
**Bad DAG** -> revert the DAG commit / pin `gitSync.ref` (1 sync period).
**Accidental data change** -> PostgreSQL PITR to a new server, copy the affected
rows back (or repoint the apps through the contract file).
**Cluster loss** -> `terraform apply` (platform layer), re-export contract (new
identity client IDs/OIDC issuer -> federated credentials are recreated by
Terraform), `install.sh`; Argo CD restores every workload. Data services are
in the separate data layer and are untouched.
**Region loss (prod)** -> geo-restore PostgreSQL in the paired region, apply
foundation/platform/data for a DR environment (`environments/dr`, same code),
restore Files from backup, repoint DNS. Target RTO for this design: hours (not a
hot standby). Hot standby would add a second region, Front Door, PostgreSQL
read replica promotion and active geo-replication for Redis.

## Restore drills (schedule)

| Drill | Frequency | Evidence |
|---|---|---|
| PostgreSQL PITR to a new server and row count check | quarterly | ticket with timings |
| File share restore from soft delete | quarterly | |
| Rebuild dev cluster from scratch (Terraform + Argo CD) | per minor AKS upgrade | time to green |
| State recovery from a previous blob version | yearly | |
