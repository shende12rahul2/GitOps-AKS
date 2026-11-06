variable "subscription_id" {
  description = "Target subscription ID."
  type        = string
}

variable "project" {
  description = "Project code."
  type        = string
  default     = "akspoc"
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "location_short" {
  description = "Short region code."
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

variable "state_resource_group_name" {
  description = "Terraform state resource group."
  type        = string
}

variable "state_storage_account_name" {
  description = "Terraform state storage account."
  type        = string
}

variable "state_container_name" {
  description = "Terraform state container for this environment."
  type        = string
}

variable "platform_admins_group_name" {
  description = "Display name of the platform administrators Entra group (PostgreSQL Entra admin principal name)."
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "17"
}

variable "postgresql_sku_name" {
  description = "PostgreSQL compute SKU."
  type        = string
  default     = "B_Standard_B2s"
}

variable "postgresql_zone" {
  description = "Primary availability zone."
  type        = string
  default     = "1"
}

variable "postgresql_high_availability_mode" {
  description = "null, SameZone or ZoneRedundant."
  type        = string
  default     = null
}

variable "postgresql_storage_mb" {
  description = "Storage in MB."
  type        = number
  default     = 32768
}

variable "postgresql_storage_tier" {
  description = "Disk performance tier."
  type        = string
  default     = "P4"
}

variable "postgresql_backup_retention_days" {
  description = "PITR window."
  type        = number
  default     = 7
}

variable "postgresql_geo_redundant_backup_enabled" {
  description = "Geo-redundant backups."
  type        = bool
  default     = false
}

variable "postgresql_pgbouncer_enabled" {
  description = "Built-in PgBouncer (not on Burstable)."
  type        = bool
  default     = false
}

variable "redis_sku_name" {
  description = "Azure Managed Redis SKU."
  type        = string
  default     = "Balanced_B0"
}

variable "redis_high_availability_enabled" {
  description = "Redis replication (SLA)."
  type        = bool
  default     = false
}

variable "files_replication_type" {
  description = "Azure Files replication (LRS, ZRS)."
  type        = string
  default     = "LRS"
}

variable "shared_files_quota_gb" {
  description = "Quota of the shared application share."
  type        = number
  default     = 10
}

variable "airflow_logs_quota_gb" {
  description = "Quota of the Airflow logs share."
  type        = number
  default     = 10
}

variable "resource_lock_level" {
  description = "Lock on the data resource group (CanNotDelete in prod)."
  type        = string
  default     = null
}
