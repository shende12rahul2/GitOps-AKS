project        = "akspoc"
environment    = "dev"
location       = "eastus2"
location_short = "eus2"
owner          = "platform-team"
cost_center    = "poc"

state_resource_group_name  = "rg-akspoc-tfstate-eus2"
state_storage_account_name = "REPLACE_WITH_STATE_ACCOUNT"
state_container_name       = "tfstate-dev"

github_organization = "REPLACE_WITH_GITHUB_ORG"

# Created by bootstrap/entra/create-groups.sh (object IDs are not secrets).
entra_group_object_ids = {
  platform_admins = "00000000-0000-0000-0000-000000000001"
  devops          = "00000000-0000-0000-0000-000000000002"
  developers      = "00000000-0000-0000-0000-000000000003"
  qa              = "00000000-0000-0000-0000-000000000004"
  readers         = "00000000-0000-0000-0000-000000000005"
}

kubernetes_version = "1.36"
aks_sku_tier       = "Free"

# Sizing: see docs/aks-sizing.md (requests-based calculation).
system_node_pool = {
  vm_size         = "Standard_D2ads_v5"
  min_count       = 1
  max_count       = 2
  os_disk_size_gb = 64
}

user_node_pools = {
  apps = {
    vm_size         = "Standard_D4ads_v5"
    min_count       = 2
    max_count       = 3
    os_disk_size_gb = 128
  }
}

ingress_mode       = "agic"
appgw_sku          = "WAF_v2"
appgw_waf_mode     = "Detection" # tune in dev, Prevention in test/prod
appgw_min_capacity = 0
appgw_max_capacity = 2

acr_sku                      = "Standard"
acr_private_endpoint_enabled = false

key_vault_purge_protection_enabled = true
key_vault_soft_delete_days         = 7

log_retention_days = 30
log_daily_quota_gb = 2

defender_enabled            = false
deployment_safeguards_level = "Warn"

jumpbox_enabled = false
bastion_sku     = "Developer"
