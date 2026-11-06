# Apache Airflow

Official Helm chart **1.22.0**, Airflow **3.2.2**, release `airflow` in
namespace `airflow`, deployed by Argo CD from `platform/airflow/values.yaml`.

## Components

| Component | Replicas (dev/prod) | Notes |
|---|---|---|
| api-server (UI + REST API v2 + execution API) | 1 / 2 | Entra ID SSO (FAB OAuth) |
| scheduler | 1 / 2 | |
| dag-processor | 1 / 1 | standalone (mandatory in Airflow 3), git-sync sidecar |
| triggerer | 1 / 1 | deferrable operators |
| Celery workers | 1 / 2 | concurrency 4, git-sync sidecar |
| statsd exporter | 1 | scraped by managed Prometheus |
| migrate-database Job | per sync | Argo CD Sync hook |
| bundled PostgreSQL / Redis / PgBouncer | **disabled** | managed services instead |

## Executor decision: CeleryExecutor on Azure Managed Redis

**Requirement**: confirm Celery/Kombu compatibility before provisioning.

| Concern | Finding | Configuration |
|---|---|---|
| Redis Cluster protocol | Kombu's Redis transport is a single-node client (multi-key `BRPOP`, `MULTI/EXEC`, sorted sets for unacked messages). `OSSCluster` breaks it; `EnterpriseCluster` rejects cross-slot multi-key commands. | `clustering_policy = "NoCluster"` (standalone semantics, supported up to 25 GB; Microsoft lists "message broker" as its use case). |
| Database index | Azure Managed Redis exposes database 0 only. | `rediss://:<key>@host:10000/0` |
| TLS | Kombu supports `rediss://`. The Celery provider (3.20.0 in Airflow 3.2.2 constraints) builds `broker_use_ssl={"ssl_cert_reqs": CERT_REQUIRED}` when `[celery] ssl_active=True`; `ssl_mutual_tls` defaults to True and must be False without client certificates. | `ssl_active=True`, `ssl_mutual_tls=False`, port 10000 |
| Authentication | Celery cannot refresh Entra tokens. | access key (Key Vault `airflow-broker-url`); apps use Entra |
| Eviction | Broker keys have no TTL; eviction loses tasks. | `NoEviction` + memory alert at 75 %; cache keys always TTL'd |
| Key isolation | Kombu `global_keyprefix` (Kombu >= 5.3). | `[celery_broker_transport_options] global_keyprefix = airflow:` |
| Redelivery | Visibility timeout default 24 h in Airflow. | `visibility_timeout = 21600` |

Evidence collected while building this POC (see [validation-report.md](validation-report.md)):
code inspection of `apache-airflow-providers-celery` 3.20.0 and Kombu 5.7, and a
full local CeleryExecutor run (api-server, scheduler, dag-processor, Celery
worker) against Redis with `noeviction` and the `airflow:` prefix, with the
metadata DB on PostgreSQL as the least-privilege `airflow` role. Not verifiable
outside Azure: TLS on port 10000 against Azure Managed Redis itself; validate
in-cluster with:

```bash
kubectl -n airflow exec deploy/airflow-worker -c worker -- celery --app airflow.providers.celery.executors.celery_executor.app inspect ping
kubectl -n airflow exec deploy/airflow-scheduler -c scheduler -- airflow dags trigger dag_sync_canary
```

**Fallback** if broker behaviour is not acceptable: switch to
`executor: KubernetesExecutor` (no broker at all; one pod per task, slower
start-up), remove `data.brokerUrlSecretName`, and keep Redis for application
caching only. Production alternative: a dedicated Managed Redis instance for the
broker so cache load can never affect task delivery.

### Shared Redis limitations

- One access key = full access: Airflow could read application cache keys.
  Applications use Entra (separate identities), but Airflow's key is not scoped.
- `NoEviction` makes a full instance reject writes for **both** consumers.
- A noisy cache workload adds latency to task scheduling.
- Production: separate instances (or at least separate databases on a
  clustered tier that supports them) and per-identity access policies.

## Secrets

All from Key Vault through the CSI driver (`platform/secrets`), synced to
Kubernetes Secrets by the `airflow-kv-sync` pod (workload identity
`id-...-airflow`, secret-scoped RBAC):

| Kubernetes Secret | Key | Key Vault secret | Source |
|---|---|---|---|
| airflow-metadata | connection | airflow-metadata-connection | Terraform |
| airflow-broker-url | connection | airflow-broker-url | Terraform |
| airflow-fernet-key | fernet-key | airflow-fernet-key | Terraform |
| airflow-api-secret-key | api-secret-key | airflow-api-secret-key | Terraform |
| airflow-jwt-secret | jwt-secret | airflow-jwt-secret | Terraform |
| airflow-webserver-secret-key | webserver-secret-key | airflow-webserver-secret-key | Terraform |
| airflow-gitsync-ssh | gitSshKey | airflow-gitsync-ssh-key | operator |
| airflow-oauth | client-secret | airflow-oauth-client-secret | Entra script |
| airflow-internal-api | INTERNAL_API_KEY | internal-api-key | Terraform |

## GitHub-managed DAGs with Git-Sync: setup

1. **Repository**: create `aks-microservices-app` (private). DAGs live in `airflow/dags/`.
2. **Deploy key** (read-only, repository-scoped):
   ```bash
   ssh-keygen -t ed25519 -C "airflow-gitsync-dev" -N '' -f ./gitsync
   gh repo deploy-key add ./gitsync.pub --repo <org>/aks-microservices-app --title airflow-gitsync-dev
   ```
   Do not tick "Allow write access".
3. **Store securely** (never in Git):
   ```bash
   ../aks-infrastructure-iac/scripts/set-operator-secret.sh <key-vault> airflow-gitsync-ssh-key ./gitsync
   shred -u ./gitsync ./gitsync.pub
   ```
4. **Configure Git-Sync** in `platform/airflow/values.yaml` (`dags.gitSync`):
   `repo: git@github.com:<org>/aks-microservices-app.git`, `sshKeySecret: airflow-gitsync-ssh`,
   `knownHosts` (GitHub host keys, verified against GitHub's published fingerprints).
5. **Branch and directory**: `ref: main`, `subPath: airflow/dags`, `depth: 1`.
6. **Synchronisation**: `period: 60s`, `maxFailures: 3`. Branch protection on
   `main` requires `validate-dags`, so only validated DAGs are synced.
7. **Shared visibility**: every component that parses or runs DAGs
   (dag-processor, workers, triggerer) has its own git-sync sidecar pulling the
   same commit into the chart's shared `dags` emptyDir. No RWX volume is needed
   for DAGs; components converge within one period.
8. **Validate discovery**:
   ```bash
   kubectl -n airflow logs deploy/airflow-dag-processor -c git-sync --tail=20
   kubectl -n airflow exec deploy/airflow-dag-processor -c dag-processor -- airflow dags list
   kubectl -n airflow exec deploy/airflow-dag-processor -c dag-processor -- airflow dags list-import-errors
   ```
9. **Run a sample DAG**: UI -> `order_processing_pipeline` -> unpause -> Trigger,
   or `airflow dags trigger order_processing_pipeline`.
10. **Update a DAG**: bump `DAG_VERSION` in `airflow/dags/dag_sync_canary.py` via PR.
11. **Verify automatic sync**: after merge, within ~60 s the DAG description shows
    the new version (`airflow dags details dag_sync_canary`). Measured locally: the
    DAG processor picked up a changed file within ~5 s of it appearing.
12. **Troubleshooting**:

    | Symptom | Check |
    |---|---|
    | `Permission denied (publickey)` | deploy key added to the right repo; KV secret content; `kubectl -n airflow get secret airflow-gitsync-ssh` |
    | `Host key verification failed` | `knownHosts` vs GitHub fingerprints |
    | git-sync can't connect | NetworkPolicy egress :22; NSG/firewall to github.com |
    | DAG missing | `subPath`, `list-import-errors`, dag-processor logs |
    | `ModuleNotFoundError` | package not in the image: add to `airflow/requirements.txt`, rebuild, promote image |

13. **Rollback a bad DAG**: revert the commit on `main` (Git-Sync picks up the
    revert), or pin `dags.gitSync.ref` to a known-good SHA in
    `environments/<env>/platform/airflow.yaml` through a GitOps PR.

## Sample DAGs

| DAG | What it does |
|---|---|
| `order_processing_pipeline` (hourly) | checks health of 4 services (mapped) -> users -> in-stock products -> creates 2 test orders -> `process-pending` -> verifies every notification file via the Notification Service |
| `shared_storage_check` (daily) | every service writes/reads a marker on Azure Files; user-service writes, order-service reads back |
| `dag_sync_canary` (manual) | Git-Sync canary |
