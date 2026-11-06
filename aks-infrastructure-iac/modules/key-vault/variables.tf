variable "name" {
  description = "Key Vault name (3-24 chars, globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault name must be 3-24 alphanumerics/hyphens, start with a letter and not end with a hyphen."
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

variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "purge_protection_enabled" {
  description = "Enable purge protection (recommended; irreversible)."
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention (7-90 days)."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be 7-90."
  }
}

variable "public_network_access_enabled" {
  description = "Enable the public endpoint (firewall default-deny, only allowed_ip_ranges). false (default) = private endpoint and ARM control plane only."
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "Public IPs/CIDRs allowed through the firewall when public_network_access_enabled = true."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_ip_ranges) == 0 || var.public_network_access_enabled
    error_message = "allowed_ip_ranges requires public_network_access_enabled = true."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the Key Vault private endpoint."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of privatelink.vaultcore.azure.net."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for audit logs."
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
