output "resource_group_name" {
  description = "Data resource group."
  value       = module.rg_data.name
}

output "postgresql_fqdn" {
  description = "PostgreSQL FQDN (private DNS)."
  value       = module.postgresql.fqdn
}

output "postgresql_server_name" {
  description = "PostgreSQL server name."
  value       = module.postgresql.name
}

output "redis_hostname" {
  description = "Managed Redis hostname."
  value       = module.redis.hostname
}

output "redis_port" {
  description = "Managed Redis TLS port."
  value       = module.redis.port
}

output "storage_account_name" {
  description = "Azure Files storage account."
  value       = module.storage_files.name
}

output "file_share_names" {
  description = "Azure Files shares (statically provisioned in Kubernetes)."
  value       = module.file_shares.share_names
}

output "key_vault_secret_names" {
  description = "Key Vault secrets consumed by workloads."
  value       = concat(keys(module.secret), keys(module.operator_secret))
}
