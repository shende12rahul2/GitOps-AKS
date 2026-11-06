variable "subscription_id" {
  description = "Target subscription ID."
  type        = string
}

variable "project" {
  description = "Project code used in names."
  type        = string
  default     = "akspoc"
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "location" {
  description = "Azure region. Must offer AKS, Azure Managed Redis, PostgreSQL Flexible Server and Application Gateway v2."
  type        = string
}

variable "location_short" {
  description = "Short region code used in names."
  type        = string
}

variable "owner" {
  description = "Owning team (tag)."
  type        = string
}

variable "cost_center" {
  description = "Cost center (tag)."
  type        = string
}

variable "vnet_cidr" {
  description = "Environment VNet CIDR (/16). Unique per environment so the VNets can be peered to a hub later."
  type        = string

  validation {
    condition     = can(cidrhost(var.vnet_cidr, 0)) && endswith(var.vnet_cidr, "/16")
    error_message = "vnet_cidr must be a valid /16 CIDR."
  }
}

variable "app_dns_zone_name" {
  description = "Private DNS zone for application and admin hostnames (app., argocd., airflow.)."
  type        = string
  default     = "poc.example.com"
}

variable "appgw_public_frontend_enabled" {
  description = "Plan for a public App Gateway frontend (adds NSG rule, removes private-only subnet delegation)."
  type        = bool
  default     = false
}

variable "appgw_public_source_prefixes" {
  description = "Source prefixes allowed to the public frontend (Internet, or a list of client CIDRs)."
  type        = list(string)
  default     = ["Internet"]
}

variable "acr_private_endpoint_enabled" {
  description = "Create the privatelink.azurecr.io zone (only when ACR Premium + private endpoint is used)."
  type        = bool
  default     = false
}

variable "nat_gateway_enabled" {
  description = "Create a NAT Gateway for the node and management subnets."
  type        = bool
  default     = false
}

variable "bastion_standard_subnet_enabled" {
  description = "Create AzureBastionSubnet (only needed for Bastion Standard)."
  type        = bool
  default     = false
}

variable "resource_lock_level" {
  description = "Lock on the network resource group (null for dev, CanNotDelete for prod)."
  type        = string
  default     = null
}
