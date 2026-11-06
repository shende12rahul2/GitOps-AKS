variable "name" {
  description = "Registry name (5-50 alphanumerics, globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "ACR names must be 5-50 alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "sku" {
  description = "Basic, Standard or Premium. Premium is required for private endpoints, firewall rules, retention and geo-replication."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}

variable "public_network_access_enabled" {
  description = "Premium only: allow the public endpoint (needed by GitHub-hosted runners unless self-hosted runners in the VNet are used)."
  type        = bool
  default     = true
}

variable "private_endpoint_enabled" {
  description = "Create a private endpoint (Premium only)."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Private endpoint subnet ID (required when private_endpoint_enabled)."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "privatelink.azurecr.io zone ID (required when private_endpoint_enabled)."
  type        = string
  default     = null
}

variable "untagged_retention_days" {
  description = "Premium only: days before untagged manifests are purged."
  type        = number
  default     = 7
}

variable "zone_redundancy_enabled" {
  description = "Premium only: zone redundancy."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for registry audit logs."
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics_enabled" {
  description = "Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply."
  type        = bool
  default     = false
}
