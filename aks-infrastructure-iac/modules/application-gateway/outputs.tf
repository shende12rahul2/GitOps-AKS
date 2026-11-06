output "id" {
  description = "Application Gateway ID (AGIC target)."
  value       = azurerm_application_gateway.this.id
}

output "name" {
  description = "Application Gateway name."
  value       = azurerm_application_gateway.this.name
}

output "private_ip_address" {
  description = "Private frontend IP (target of private DNS A records)."
  value       = var.private_ip_address
}

output "public_ip_address" {
  description = "Public frontend IP (null when private-only)."
  value       = try(azurerm_public_ip.this[0].ip_address, null)
}

output "waf_policy_id" {
  description = "WAF policy ID (null for Standard_v2)."
  value       = try(azurerm_web_application_firewall_policy.this[0].id, null)
}
