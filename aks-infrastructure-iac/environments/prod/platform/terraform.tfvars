project        = "akspoc"
environment    = "prod"
location       = "eastus2"
location_short = "eus2"
owner          = "platform-team"
cost_center    = "prod"

state_resource_group_name  = "rg-akspoc-tfstate-eus2"
state_storage_account_name = "REPLACE_WITH_STATE_ACCOUNT"
state_container_name       = "tfstate-prod"

github_organization = "REPLACE_WITH_GITHUB_ORG"

entra_group_object_ids = {
  platform_admins = "00000000-0000-0000-0000-000000000001"
  devops          = "00000000-0000-0000-0000-000000000002"
  developers      = "00000000-0000-0000-0000-000000000003"
  qa              = "00000000-0000-0000-0000-000000000004"
  readers         = "00000000-0000-0000-0000-000000000005"
}

kubernetes_version = "1.36"
aks_sku_tier       = "Standard" # API server SLA

system_node_pool = {
  vm_size         = "Standard_D4ads_v5"
  min_count       = 3
  max_count       = 4
  os_disk_size_gb = 128
  zones           = ["1", "2", "3"]
}

user_node_pools = {
  apps = {
    vm_size         = "Standard_D4ads_v5"
    min_count       = 3
    max_count       = 6
    os_disk_size_gb = 128
    zones           = ["1", "2", "3"]
  }
}

ingress_mode       = "agic"
appgw_sku          = "WAF_v2"
appgw_waf_mode     = "Prevention"
appgw_zones        = ["1", "2", "3"]
appgw_min_capacity = 2
appgw_max_capacity = 10

acr_sku                      = "Premium"
acr_private_endpoint_enabled = true
# promotion_source_acr_id    = "<test ACR resource ID>"

key_vault_purge_protection_enabled = true
key_vault_soft_delete_days         = 90

log_retention_days = 90
log_daily_quota_gb = -1

defender_enabled            = true
deployment_safeguards_level = "Enforce"

jumpbox_enabled = true
bastion_sku     = "Standard"
# jumpbox_bootstrap_ssh_public_key = "ssh-ed25519 AAAA... throwaway"

resource_lock_level = "CanNotDelete"
