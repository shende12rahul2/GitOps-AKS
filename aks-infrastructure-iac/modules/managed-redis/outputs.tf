output "id" {
  description = "Managed Redis ID."
  value       = azurerm_managed_redis.this.id
}

output "hostname" {
  description = "Redis hostname (resolves to the private endpoint inside the VNet)."
  value       = azurerm_managed_redis.this.hostname
}

output "port" {
  description = "TLS port (10000)."
  value       = azurerm_managed_redis.this.default_database[0].port
}

output "primary_access_key" {
  description = "Primary access key (only for the Celery broker URL, written to Key Vault)."
  value       = azurerm_managed_redis.this.default_database[0].primary_access_key
  sensitive   = true
}
