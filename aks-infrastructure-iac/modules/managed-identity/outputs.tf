output "id" {
  description = "Identity resource ID."
  value       = azurerm_user_assigned_identity.this.id
}

output "name" {
  description = "Identity name (also the PostgreSQL role name when used for Entra auth)."
  value       = azurerm_user_assigned_identity.this.name
}

output "client_id" {
  description = "Client (application) ID used by azure-identity / workload identity annotations."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Object (principal) ID used for role assignments."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "tenant_id" {
  description = "Tenant ID."
  value       = azurerm_user_assigned_identity.this.tenant_id
}
