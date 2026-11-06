# The password administrator is a break-glass account only. Its password is
# generated ephemerally and sent write-only: it is never stored in Terraform
# state, in Key Vault or anywhere else. Day-to-day administration uses Entra ID.
# Recover access with: az postgres flexible-server update --admin-password ...
ephemeral "random_password" "admin" {
  length           = 40
  special          = true
  override_special = "!#%*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = var.postgresql_version
  sku_name            = var.sku_name
  zone                = var.zone

  # Private access (VNet integration): the server is injected into a delegated
  # subnet and resolves through a private DNS zone ending in
  # .postgres.database.azure.com. No public endpoint exists.
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  storage_mb        = var.storage_mb
  storage_tier      = var.storage_tier
  auto_grow_enabled = true

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  administrator_login               = var.administrator_login
  administrator_password_wo         = ephemeral.random_password.admin.result
  administrator_password_wo_version = var.administrator_password_version

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true # only for the Airflow role (Celery/SQLAlchemy cannot refresh Entra tokens)
    tenant_id                     = var.tenant_id
  }

  dynamic "high_availability" {
    for_each = var.high_availability_mode == null ? [] : [var.high_availability_mode]

    content {
      mode = high_availability.value
    }
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 3
    start_minute = 0
  }

  tags = var.tags

  lifecycle {
    # Azure may move the primary after an HA failover.
    ignore_changes = [zone, high_availability[0].standby_availability_zone]

    precondition {
      condition     = !var.pgbouncer_enabled || !startswith(var.sku_name, "B_")
      error_message = "Built-in PgBouncer is not available on the Burstable tier."
    }
  }
}

# Entra administrators: the db-bootstrap workload identity (creates databases,
# roles and grants from a versioned in-cluster Job) and the platform admin group.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  for_each = var.entra_administrators

  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = each.value.object_id
  principal_name      = each.value.principal_name
  principal_type      = each.value.principal_type
}

locals {
  server_parameters = merge(
    {
      "require_secure_transport"              = "on"
      "ssl_min_protocol_version"              = "TLSv1.2"
      "log_min_duration_statement"            = "2000"
      "log_connections"                       = "on"
      "log_disconnections"                    = "on"
      "pg_qs.query_capture_mode"              = "top"
      "pgms_wait_sampling.query_capture_mode" = "all"
      "track_io_timing"                       = "on"
    },
    var.pgbouncer_enabled ? {
      "pgbouncer.enabled"           = "true"
      "pgbouncer.default_pool_size" = "20"
      "pgbouncer.pool_mode"         = "transaction"
    } : {},
    var.server_parameters,
  )
}

resource "azurerm_postgresql_flexible_server_configuration" "this" {
  for_each = local.server_parameters

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostics_enabled ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_postgresql_flexible_server.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = !var.alerts_enabled ? {} : {
    cpu     = { metric = "cpu_percent", threshold = 80, description = "CPU above 80% for 15 minutes" }
    storage = { metric = "storage_percent", threshold = 80, description = "Storage above 80% (auto-grow is on, but check growth)" }
    memory  = { metric = "memory_percent", threshold = 90, description = "Memory above 90%" }
  }

  name                = "alert-${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_postgresql_flexible_server.this.id]
  description         = each.value.description
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = each.value.metric
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = each.value.threshold
  }

  action {
    action_group_id = var.action_group_id
  }
}
