variable "name" {
  description = "Virtual network name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the VNet."
  type        = string
}

variable "address_space" {
  description = "VNet address space (CIDR list). Must not overlap other environments or on-premises ranges."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for c in var.address_space : can(cidrhost(c, 0))])
    error_message = "address_space must contain at least one valid CIDR."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers. Empty list = Azure-provided DNS (168.63.129.16), required for private DNS zones unless you run a resolver."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for VNet metrics (used when diagnostics_enabled = true)."
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
