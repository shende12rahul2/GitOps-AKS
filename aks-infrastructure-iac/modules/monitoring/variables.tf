variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for monitoring resources."
  type        = string
}

variable "log_analytics_name" {
  description = "Log Analytics workspace name."
  type        = string
}

variable "monitor_workspace_name" {
  description = "Azure Monitor workspace (managed Prometheus) name."
  type        = string
}

variable "action_group_name" {
  description = "Action group name for critical alerts."
  type        = string
}

variable "retention_in_days" {
  description = "Interactive retention. 30 days is included in PerGB2018 pricing; longer retention is billed."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 = unlimited). A cap protects a POC budget but drops data once reached."
  type        = number
  default     = 2
}

variable "prometheus_enabled" {
  description = "Create an Azure Monitor workspace for managed Prometheus."
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Map of receiver key => email address for the critical alert action group."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
