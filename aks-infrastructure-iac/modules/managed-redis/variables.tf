variable "name" {
  description = "Azure Managed Redis name."
  type        = string
}

variable "location" {
  description = "Azure region (check Azure Managed Redis availability)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "sku_name" {
  description = "SKU, e.g. Balanced_B0 (smallest), Balanced_B1, Balanced_B5, MemoryOptimized_M10."
  type        = string
  default     = "Balanced_B0"

  validation {
    condition     = can(regex("^(Balanced_B|MemoryOptimized_M|ComputeOptimized_X|FlashOptimized_A)[0-9]+$", var.sku_name))
    error_message = "sku_name must be an Azure Managed Redis SKU such as Balanced_B0."
  }
}

variable "high_availability_enabled" {
  description = "Replicate data across a second node. false halves cost but has no SLA (dev/test only)."
  type        = bool
  default     = false
}

variable "clustering_policy" {
  description = "NoCluster (Celery-compatible), EnterpriseCluster or OSSCluster."
  type        = string
  default     = "NoCluster"

  validation {
    condition     = contains(["NoCluster", "EnterpriseCluster", "OSSCluster"], var.clustering_policy)
    error_message = "Invalid clustering policy."
  }
}

variable "eviction_policy" {
  description = "NoEviction (safe for a shared Celery broker) or an LRU/LFU policy for cache-only instances."
  type        = string
  default     = "NoEviction"

  validation {
    condition     = contains(["NoEviction", "AllKeysLRU", "AllKeysLFU", "AllKeysRandom", "VolatileLRU", "VolatileLFU", "VolatileRandom", "VolatileTTL"], var.eviction_policy)
    error_message = "Invalid eviction policy."
  }
}

variable "access_keys_authentication_enabled" {
  description = "Allow access-key authentication (required by Celery)."
  type        = bool
  default     = true
}

variable "rdb_backup_frequency" {
  description = "RDB persistence frequency (1h, 6h, 12h) or null for no persistence."
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Private endpoint subnet."
  type        = string
}

variable "private_dns_zone_id" {
  description = "privatelink.redis.azure.net zone ID."
  type        = string
}

variable "entra_access_object_ids" {
  description = "Map of stable key => principal object ID granted the default data access policy."
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for metrics."
  type        = string
  default     = null
}

variable "action_group_id" {
  description = "Action group for alerts (used when alerts_enabled = true)."
  type        = string
  default     = null
}

variable "memory_alert_threshold_percent" {
  description = "Memory usage alert threshold."
  type        = number
  default     = 75
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
