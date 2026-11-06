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

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Azure Managed Redis name. | `string` |  | yes |
| `location` | Azure region (check Azure Managed Redis availability). | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `sku_name` | SKU, e.g. Balanced_B0 (smallest), Balanced_B1, Balanced_B5, MemoryOptimized_M10. | `string` | `Balanced_B0` | no |
| `high_availability_enabled` | Replicate data across a second node. false halves cost but has no SLA (dev/test only). | `bool` | `false` | no |
| `clustering_policy` | NoCluster (Celery-compatible), EnterpriseCluster or OSSCluster. | `string` | `NoCluster` | no |
| `eviction_policy` | NoEviction (safe for a shared Celery broker) or an LRU/LFU policy for cache-only instances. | `string` | `NoEviction` | no |
| `access_keys_authentication_enabled` | Allow access-key authentication (required by Celery). | `bool` | `true` | no |
| `rdb_backup_frequency` | RDB persistence frequency (1h, 6h, 12h) or null for no persistence. | `string` | `null` | no |
| `private_endpoint_subnet_id` | Private endpoint subnet. | `string` |  | yes |
| `private_dns_zone_id` | privatelink.redis.azure.net zone ID. | `string` |  | yes |
| `entra_access_object_ids` | Map of stable key => principal object ID granted the default data access policy. | `map(string)` | `{}` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for metrics. | `string` | `null` | no |
| `action_group_id` | Action group for alerts (used when alerts_enabled = true). | `string` | `null` | no |
| `memory_alert_threshold_percent` | Memory usage alert threshold. | `number` | `75` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |
| `alerts_enabled` | Create metric alerts routed to action_group_id (explicit flag keeps count known at plan time). | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Managed Redis ID. |
| `hostname` | Redis hostname (resolves to the private endpoint inside the VNet). |
| `port` | TLS port (10000). |
| `primary_access_key` | Primary access key (only for the Celery broker URL, written to Key Vault). |
