output "zone_ids" {
  description = "Map of zone name => zone ID."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "zone_names" {
  description = "Zone names."
  value       = keys(azurerm_private_dns_zone.this)
}
