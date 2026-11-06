variable "name" {
  description = "Server name (globally unique, 3-63 lowercase chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "Server name must be 3-63 lowercase letters, digits or hyphens."
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

variable "postgresql_version" {
  description = "Major PostgreSQL version."
  type        = string
  default     = "17"

  validation {
    condition     = contains(["15", "16", "17", "18"], var.postgresql_version)
    error_message = "Use a currently supported major version (15-18)."
  }
}

variable "sku_name" {
  description = "Compute SKU: B_Standard_B2s (POC), GP_Standard_D2ds_v5 (production, built-in PgBouncer)."
  type        = string
  default     = "B_Standard_B2s"

  validation {
    condition     = can(regex("^(B|GP|MO)_Standard_", var.sku_name))
    error_message = "sku_name must start with B_, GP_ or MO_Standard_."
  }
}

variable "zone" {
  description = "Availability zone for the primary (null = no preference)."
  type        = string
  default     = "1"
}

variable "high_availability_mode" {
  description = "null (POC), SameZone or ZoneRedundant (production). Not available on Burstable."
  type        = string
  default     = null

  validation {
    condition     = var.high_availability_mode == null || contains(["SameZone", "ZoneRedundant"], coalesce(var.high_availability_mode, "x"))
    error_message = "high_availability_mode must be null, SameZone or ZoneRedundant."
  }
}

variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ending in .postgres.database.azure.com, linked to the VNet."
  type        = string
}

variable "storage_mb" {
  description = "Storage size in MB (32768 = 32 GiB, smallest)."
  type        = number
  default     = 32768
}

variable "storage_tier" {
  description = "Premium SSD performance tier for the disk (P4 for 32 GiB)."
  type        = string
  default     = "P4"
}

variable "backup_retention_days" {
  description = "Point-in-time restore window (7-35 days)."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be 7-35."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Geo-redundant backups (set at creation; production DR)."
  type        = bool
  default     = false
}

variable "administrator_login" {
  description = "Break-glass password administrator login."
  type        = string
  default     = "pgbreakglass"
}

variable "administrator_password_version" {
  description = "Increment to rotate the (discarded) break-glass password."
  type        = number
  default     = 1
}

variable "entra_administrators" {
  description = "Map of key => Entra administrator (identity or group)."
  type = map(object({
    object_id      = string
    principal_name = string
    principal_type = string
  }))

  validation {
    condition     = alltrue([for a in values(var.entra_administrators) : contains(["User", "Group", "ServicePrincipal"], a.principal_type)])
    error_message = "principal_type must be User, Group or ServicePrincipal."
  }
}

variable "pgbouncer_enabled" {
  description = "Enable the built-in PgBouncer on port 6432 (General Purpose / Memory Optimized only)."
  type        = bool
  default     = false
}

variable "server_parameters" {
  description = "Additional server parameters (override defaults)."
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for logs and metrics."
  type        = string
  default     = null
}

variable "action_group_id" {
  description = "Action group for alerts (used when alerts_enabled = true)."
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

variable "alerts_enabled" {
  description = "Create metric alerts routed to action_group_id (explicit flag keeps count known at plan time)."
  type        = bool
  default     = false
}
