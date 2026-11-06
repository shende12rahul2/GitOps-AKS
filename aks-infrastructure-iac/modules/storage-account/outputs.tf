output "id" {
  description = "Storage account ID."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "primary_file_host" {
  description = "File endpoint host (<name>.file.core.windows.net, resolves privately)."
  value       = azurerm_storage_account.this.primary_file_host
}
