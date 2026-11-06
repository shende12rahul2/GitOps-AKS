project        = "akspoc"
environment    = "dev"
location       = "eastus2"
location_short = "eus2"
owner          = "platform-team"
cost_center    = "poc"

state_resource_group_name  = "rg-akspoc-tfstate-eus2"
state_storage_account_name = "REPLACE_WITH_STATE_ACCOUNT"
state_container_name       = "tfstate-dev"

platform_admins_group_name = "grp-akspoc-platform-admins"

postgresql_version                      = "17"
postgresql_sku_name                     = "B_Standard_B2s"
postgresql_high_availability_mode       = null
postgresql_storage_mb                   = 32768
postgresql_storage_tier                 = "P4"
postgresql_backup_retention_days        = 7
postgresql_geo_redundant_backup_enabled = false
postgresql_pgbouncer_enabled            = false

redis_sku_name                  = "Balanced_B0"
redis_high_availability_enabled = false

files_replication_type = "LRS"
shared_files_quota_gb  = 10
airflow_logs_quota_gb  = 10
