module "naming" {
  source = "../../../modules/naming"

  project         = var.project
  environment     = var.environment
  location_short  = var.location_short
  subscription_id = var.subscription_id
  layer           = "data"
  owner           = var.owner
  cost_center     = var.cost_center
}

locals {
  names = module.naming.names
  tags  = module.naming.tags
  pe    = local.foundation.subnet_ids["snet-private-endpoints"]
  zones = local.foundation.private_dns_zone_ids
}

module "rg_data" {
  source = "../../../modules/resource-group"

  name       = local.names.rg_data
  location   = var.location
  lock_level = var.resource_lock_level
  tags       = local.tags
}

# --- PostgreSQL Flexible Server (VNet integration, Entra auth) ---------------------
# Databases, roles and grants are NOT created here. Databases created through ARM
# are owned by an internal role, so the Entra administrator could not create
# schemas or grant on them. They are created in SQL by the versioned db-bootstrap
# Job (aks-gitops-deployment/platform/database), running as the Entra admin
# workload identity. See docs/database.md.
module "postgresql" {
  source = "../../../modules/postgresql"

  name                         = local.names.postgresql
  location                     = var.location
  resource_group_name          = module.rg_data.name
  tenant_id                    = local.platform.tenant_id
  postgresql_version           = var.postgresql_version
  sku_name                     = var.postgresql_sku_name
  zone                         = var.postgresql_zone
  high_availability_mode       = var.postgresql_high_availability_mode
  storage_mb                   = var.postgresql_storage_mb
  storage_tier                 = var.postgresql_storage_tier
  backup_retention_days        = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled = var.postgresql_geo_redundant_backup_enabled
  pgbouncer_enabled            = var.postgresql_pgbouncer_enabled
  delegated_subnet_id          = local.foundation.subnet_ids["snet-postgresql"]
  private_dns_zone_id          = local.zones[local.foundation.postgres_dns_zone_name]

  entra_administrators = {
    db-bootstrap = {
      object_id      = local.wi["db-bootstrap"].principal_id
      principal_name = local.wi["db-bootstrap"].name
      principal_type = "ServicePrincipal"
    }
    platform-admins = {
      object_id      = local.groups.platform_admins
      principal_name = var.platform_admins_group_name
      principal_type = "Group"
    }
  }

  diagnostics_enabled        = true
  log_analytics_workspace_id = local.platform.log_analytics_workspace_id
  alerts_enabled             = true
  action_group_id            = local.platform.action_group_id
  tags                       = local.tags
}

# --- Azure Managed Redis (private endpoint, TLS, NoCluster, NoEviction) --------------
module "redis" {
  source = "../../../modules/managed-redis"

  name                               = local.names.redis
  location                           = var.location
  resource_group_name                = module.rg_data.name
  sku_name                           = var.redis_sku_name
  high_availability_enabled          = var.redis_high_availability_enabled
  clustering_policy                  = "NoCluster"
  eviction_policy                    = "NoEviction"
  access_keys_authentication_enabled = true
  private_endpoint_subnet_id         = local.pe
  private_dns_zone_id                = local.zones["privatelink.redis.azure.net"]

  # Passwordless (Entra ID) data access for the services that cache.
  entra_access_object_ids = {
    product-service = local.wi["product-service"].principal_id
    order-service   = local.wi["order-service"].principal_id
  }

  diagnostics_enabled        = true
  log_analytics_workspace_id = local.platform.log_analytics_workspace_id
  alerts_enabled             = true
  action_group_id            = local.platform.action_group_id
  tags                       = local.tags
}

# --- Azure Files (SMB 3.1.1, private endpoint, managed-identity mounts, no keys) -------
module "storage_files" {
  source = "../../../modules/storage-account"

  name                       = local.names.storage_files
  location                   = var.location
  resource_group_name        = module.rg_data.name
  account_kind               = "StorageV2"
  account_tier               = "Standard"
  replication_type           = var.files_replication_type
  shared_access_key_enabled  = false
  smb_oauth_enabled          = true
  private_endpoints          = { file = local.zones["privatelink.file.core.windows.net"] }
  private_endpoint_subnet_id = local.pe
  diagnostics_enabled        = true
  log_analytics_workspace_id = local.platform.log_analytics_workspace_id
  tags                       = local.tags
}

module "file_shares" {
  source = "../../../modules/azure-files"

  storage_account_id  = module.storage_files.id
  resource_group_name = module.rg_data.name
  shares = {
    "shared-files" = { quota_gb = var.shared_files_quota_gb, purpose = "cross-service shared storage (/mnt/shared)" }
    "airflow-logs" = { quota_gb = var.airflow_logs_quota_gb, purpose = "Airflow task logs" }
  }
  alerts_enabled  = true
  action_group_id = local.platform.action_group_id
}
