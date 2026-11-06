resource "azurerm_managed_redis" "this" {
  name                      = var.name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  sku_name                  = var.sku_name
  high_availability_enabled = var.high_availability_enabled
  public_network_access     = "Disabled"
  tags                      = var.tags

  default_database {
    # Clients connect to <name>.<region>.redis.azure.net:10000 over TLS.
    client_protocol = "Encrypted"

    # NoCluster = a single shard that behaves like a standalone Redis server.
    # Celery/Kombu's Redis transport needs multi-key commands (BRPOP over several
    # queues, MULTI/EXEC pipelines, ZADD/HSET for unacked messages) and does not
    # speak the Redis Cluster protocol, so OSSCluster would break it and
    # EnterpriseCluster would reject cross-slot commands. NoCluster is supported
    # on SKUs up to 25 GB, which covers every POC/dev size.
    clustering_policy = var.clustering_policy

    # NoEviction: Redis returns OOM errors instead of silently deleting keys.
    # Celery queues have no TTL, and evicting them would lose Airflow tasks.
    # Application cache keys always carry a TTL, and memory is alerted at 75%.
    eviction_policy = var.eviction_policy

    # Celery cannot refresh Entra tokens, so Airflow uses the access key (stored
    # in Key Vault). Applications use Entra ID (workload identity) instead.
    access_keys_authentication_enabled = var.access_keys_authentication_enabled

    persistence_redis_database_backup_frequency = var.rdb_backup_frequency
  }

  lifecycle {
    precondition {
      # SKU suffixes of 50 and above are larger than 25 GB.
      condition     = var.clustering_policy != "NoCluster" || tonumber(regex("[0-9]+$", var.sku_name)) < 50
      error_message = "The NoCluster policy only applies to SKUs of 25 GB or less."
    }
  }
}

module "private_endpoint" {
  source = "../private-endpoint"

  name                 = "pe-${var.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  subnet_id            = var.private_endpoint_subnet_id
  target_resource_id   = azurerm_managed_redis.this.id
  subresource_name     = "redisEnterprise"
  private_dns_zone_ids = [var.private_dns_zone_id]
  tags                 = var.tags
}

# Entra ID data-plane access for each workload identity (passwordless).
resource "azurerm_managed_redis_access_policy_assignment" "this" {
  for_each = var.entra_access_object_ids

  managed_redis_id = azurerm_managed_redis.this.id
  object_id        = each.value
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostics_enabled ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_managed_redis.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "memory" {
  count = var.alerts_enabled ? 1 : 0

  name                = "alert-${var.name}-memory"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_managed_redis.this.id]
  description         = "Redis memory above ${var.memory_alert_threshold_percent}%: with NoEviction, writes (including Celery enqueues) fail when memory is full."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace       = "Microsoft.Cache/redisEnterprise"
    metric_name            = "usedmemorypercentage"
    aggregation            = "Maximum"
    operator               = "GreaterThan"
    threshold              = var.memory_alert_threshold_percent
    skip_metric_validation = true
  }

  action {
    action_group_id = var.action_group_id
  }
}
