variable "subscription_id" {
  description = "Target subscription ID."
  type        = string
}

variable "project" {
  description = "Project code."
  type        = string
  default     = "akspoc"
}

variable "location" {
  description = "Region for the state account."
  type        = string
  default     = "eastus2"
}

variable "location_short" {
  description = "Short region code."
  type        = string
  default     = "eus2"
}

variable "owner" {
  description = "Owning team."
  type        = string
  default     = "platform-team"
}

variable "environments" {
  description = "Environments that get a state container and pipeline identities."
  type        = list(string)
  default     = ["dev", "test", "prod"]
}

variable "state_replication_type" {
  description = "Replication for the state account (GRS/RAGRS keeps a copy in the paired region)."
  type        = string
  default     = "RAGRS"
}

variable "allowed_ip_ranges" {
  description = "Optional public egress IPs allowed to reach the state account. Empty = Entra-protected public endpoint."
  type        = list(string)
  default     = []
}

variable "github_organization" {
  description = "GitHub organization or user that owns the repositories."
  type        = string
}

variable "infrastructure_repository" {
  description = "Infrastructure repository name."
  type        = string
  default     = "aks-infrastructure-iac"
}

variable "platform_admins_group_object_id" {
  description = "Entra group object ID of platform administrators (state break-glass)."
  type        = string
}
