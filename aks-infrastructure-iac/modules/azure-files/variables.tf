variable "storage_account_id" {
  description = "Storage account ID hosting the shares."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for alert rules."
  type        = string
}

variable "shares" {
  description = "Map of share name => settings."
  type = map(object({
    quota_gb    = number
    protocol    = optional(string, "SMB")
    access_tier = optional(string, "TransactionOptimized")
    purpose     = optional(string, "shared")
  }))

  validation {
    condition     = alltrue([for k, v in var.shares : can(regex("^[a-z0-9](?:[a-z0-9]|-[a-z0-9]){2,62}$", k)) && contains(["SMB", "NFS"], v.protocol) && v.quota_gb >= 1])
    error_message = "Share names must be 3-63 lowercase alphanumerics/single hyphens; protocol SMB or NFS; quota >= 1 GiB."
  }
}

variable "capacity_alert_percent" {
  description = "Quota usage percentage that triggers an alert."
  type        = number
  default     = 80
}

variable "action_group_id" {
  description = "Action group for alerts (used when alerts_enabled = true)."
  type        = string
  default     = null
}

variable "alerts_enabled" {
  description = "Create metric alerts routed to action_group_id (explicit flag keeps count known at plan time)."
  type        = bool
  default     = false
}
