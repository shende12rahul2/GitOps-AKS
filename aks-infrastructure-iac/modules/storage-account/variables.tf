variable "name" {
  description = "Storage account name (3-24 lowercase alphanumerics, globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account names must be 3-24 lowercase letters or digits."
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

variable "account_kind" {
  description = "StorageV2 (Standard SMB shares) or FileStorage (Premium SMB/NFS shares)."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "FileStorage"], var.account_kind)
    error_message = "account_kind must be StorageV2 or FileStorage."
  }
}

variable "account_tier" {
  description = "Standard (pay-as-you-go HDD) or Premium (provisioned SSD, required for NFS)."
  type        = string
  default     = "Standard"
}

variable "replication_type" {
  description = "LRS (POC), ZRS (production), GRS/GZRS (Standard only, DR)."
  type        = string
  default     = "LRS"
}

variable "https_traffic_only_enabled" {
  description = "Require encryption in transit (must be false for NFS shares without EiT)."
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = "Allow account-key/SAS auth. false = Entra only (requires managed-identity SMB mounts)."
  type        = bool
  default     = false
}

variable "smb_oauth_enabled" {
  description = "Enable SMB OAuth so managed identities can mount SMB shares without keys."
  type        = bool
  default     = true
}

variable "share_soft_delete_days" {
  description = "Soft delete retention for file shares."
  type        = number
  default     = 7
}

variable "private_endpoints" {
  description = "Map of storage subresource (file, blob, ...) => private DNS zone ID."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : contains(["file", "blob", "queue", "table", "dfs", "web"], k)])
    error_message = "Keys must be storage subresource names (file, blob, queue, table, dfs, web)."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Private endpoint subnet."
  type        = string
}

variable "file_log_categories" {
  description = "File service log categories (StorageRead, StorageWrite, StorageDelete)."
  type        = list(string)
  default     = ["StorageWrite", "StorageDelete"]
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace."
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
