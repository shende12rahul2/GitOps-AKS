output "resource_group_name" {
  description = "State resource group."
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "State storage account."
  value       = azurerm_storage_account.state.name
}

output "containers" {
  description = "State containers per environment."
  value       = { for k, c in azurerm_storage_container.state : k => c.name }
}

output "github_identities" {
  description = "Client IDs to store as GitHub environment variables (AZURE_CLIENT_ID)."
  value       = { for k, i in azurerm_user_assigned_identity.github : k => i.client_id }
}

output "tenant_id" {
  description = "Tenant ID (AZURE_TENANT_ID)."
  value       = data.azurerm_client_config.current.tenant_id
}
