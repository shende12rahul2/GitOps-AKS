output "resource_group_name" {
  description = "Network resource group."
  value       = module.rg_network.name
}

output "location" {
  description = "Region."
  value       = var.location
}

output "vnet_id" {
  description = "VNet ID."
  value       = module.vnet.id
}

output "vnet_name" {
  description = "VNet name."
  value       = module.vnet.name
}

output "subnet_ids" {
  description = "Map of subnet name => ID."
  value       = { for k, s in module.subnet : k => s.id }
}

output "subnet_cidrs" {
  description = "Address plan."
  value       = local.subnet_cidrs
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone name => ID."
  value       = module.private_dns.zone_ids
}

output "postgres_dns_zone_name" {
  description = "Private DNS zone used by the PostgreSQL VNet integration."
  value       = local.names.postgres_dns_zone
}

output "app_dns_zone_name" {
  description = "Private DNS zone for application hostnames."
  value       = var.app_dns_zone_name
}

output "nat_gateway_enabled" {
  description = "Whether a NAT Gateway is attached to the node subnet."
  value       = var.nat_gateway_enabled
}

output "appgw_public_frontend_enabled" {
  description = "Whether the gateway subnet was prepared for a public frontend."
  value       = var.appgw_public_frontend_enabled
}
