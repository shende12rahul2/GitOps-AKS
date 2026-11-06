project        = "akspoc"
environment    = "prod"
location       = "eastus2"
location_short = "eus2"
owner          = "platform-team"
cost_center    = "prod"

state_resource_group_name  = "rg-akspoc-tfstate-eus2"
state_storage_account_name = "REPLACE_WITH_STATE_ACCOUNT"
state_container_name       = "tfstate-prod"

platform_admins_group_name = "grp-akspoc-platform-admins"

postgresql_version                      = "17"
postgresql_sku_name                     = "GP_Standard_D2ds_v5"
postgresql_high_availability_mode       = "ZoneRedundant"
postgresql_storage_mb                   = 131072
postgresql_storage_tier                 = "P10"
postgresql_backup_retention_days        = 35
postgresql_geo_redundant_backup_enabled = true
postgresql_pgbouncer_enabled            = true

redis_sku_name                  = "Balanced_B5"
redis_high_availability_enabled = true

files_replication_type = "ZRS"
shared_files_quota_gb  = 100
airflow_logs_quota_gb  = 50

resource_lock_level = "CanNotDelete"
