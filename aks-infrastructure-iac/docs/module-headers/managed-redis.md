# managed-redis

Azure Managed Redis (`azurerm_managed_redis`) reachable only through a private
endpoint (`privatelink.redis.azure.net`), TLS on port 10000.

Defaults are chosen for a **shared Celery broker + application cache**:

| Setting | Value | Why |
|---|---|---|
| `clustering_policy` | `NoCluster` | Single shard, standalone-Redis semantics. Kombu's Redis transport uses multi-key commands and does not support the Redis Cluster protocol. Available up to 25 GB. |
| `eviction_policy` | `NoEviction` | Celery queues have no TTL; eviction would silently lose Airflow tasks. Cache keys always carry TTLs. |
| `access_keys_authentication_enabled` | `true` | Celery cannot refresh Entra tokens. The key is stored in Key Vault for Airflow only. |
| Entra access policy assignments | product/order services | Applications authenticate passwordlessly with workload identity. |
| `high_availability_enabled` | `false` (dev) | Halves cost; no SLA. Enable for production. |

A memory alert (default 75%) warns before `NoEviction` starts rejecting writes.
