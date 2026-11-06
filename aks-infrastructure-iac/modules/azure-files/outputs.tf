output "share_names" {
  description = "Share names."
  value       = keys(azurerm_storage_share.this)
}

output "share_ids" {
  description = "Map of share name => resource ID."
  value       = { for k, v in azurerm_storage_share.this : k => v.id }
}

output "share_urls" {
  description = "Map of share name => URL."
  value       = { for k, v in azurerm_storage_share.this : k => v.url }
}
