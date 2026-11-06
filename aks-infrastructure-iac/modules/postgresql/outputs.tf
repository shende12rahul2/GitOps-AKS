output "id" {
  description = "Server ID."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  description = "Server name."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "Server FQDN (private)."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "port" {
  description = "Direct port 5432; built-in PgBouncer uses 6432."
  value       = var.pgbouncer_enabled ? 6432 : 5432
}
