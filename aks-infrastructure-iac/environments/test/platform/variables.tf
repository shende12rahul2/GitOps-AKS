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
  description = "Terraform state resource group (for remote state lookups)."
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

variable "entra_group_object_ids" {
  description = "Entra ID group object IDs for each persona."
  type = object({
    platform_admins = string
    devops          = string
    developers      = string
    qa              = string
    readers         = string
  })
}

variable "github_organization" {
  description = "GitHub organization/user owning the repositories."
  type        = string
}

variable "app_repository" {
  description = "Application source repository (image builds)."
  type        = string
  default     = "aks-microservices-app"
}

variable "kubernetes_version" {
  description = "AKS minor version alias (az aks get-versions -l <region>)."
  type        = string
  default     = "1.36"
}

variable "aks_sku_tier" {
  description = "Free for POC, Standard for production."
  type        = string
  default     = "Free"
}

variable "system_node_pool" {
  description = "System node pool sizing."
  type = object({
    vm_size         = string
    min_count       = number
    max_count       = number
    max_pods        = optional(number, 110)
    os_disk_type    = optional(string, "Ephemeral")
    os_disk_size_gb = optional(number, 64)
    zones           = optional(list(string))
  })
}

variable "user_node_pools" {
  description = "User node pools."
  type = map(object({
    vm_size         = string
    min_count       = number
    max_count       = number
    max_pods        = optional(number, 110)
    os_sku          = optional(string, "Ubuntu")
    os_disk_type    = optional(string, "Ephemeral")
    os_disk_size_gb = optional(number, 128)
    zones           = optional(list(string))
    node_labels     = optional(map(string), {})
    node_taints     = optional(list(string), [])
    max_surge       = optional(string, "33%")
    spot            = optional(bool, false)
  }))
}

variable "ingress_mode" {
  description = "agic = Application Gateway (WAF_v2/Standard_v2) + AGIC add-on; internal = in-cluster ingress controller (Traefik) behind an internal load balancer. Never both."
  type        = string
  default     = "agic"

  validation {
    condition     = contains(["agic", "internal"], var.ingress_mode)
    error_message = "ingress_mode must be agic or internal."
  }
}

variable "ingress_hostnames" {
  description = "Record names created in the private application zone, all pointing at the ingress IP."
  type        = list(string)
  default     = ["app", "argocd", "airflow"]
}

variable "appgw_sku" {
  description = "WAF_v2 or Standard_v2."
  type        = string
  default     = "WAF_v2"
}

variable "appgw_waf_mode" {
  description = "Detection or Prevention."
  type        = string
  default     = "Prevention"
}

variable "appgw_zones" {
  description = "App Gateway zones (null = regional)."
  type        = list(string)
  default     = null
}

variable "appgw_min_capacity" {
  description = "Minimum capacity units."
  type        = number
  default     = 0
}

variable "appgw_max_capacity" {
  description = "Maximum capacity units."
  type        = number
  default     = 2
}

variable "acr_sku" {
  description = "Basic, Standard or Premium."
  type        = string
  default     = "Standard"
}

variable "acr_private_endpoint_enabled" {
  description = "Private endpoint for ACR (Premium)."
  type        = bool
  default     = false
}

variable "promotion_source_acr_id" {
  description = "Lower-environment ACR ID from which this environment's CI identity may copy image digests (null for dev)."
  type        = string
  default     = null
}

variable "key_vault_purge_protection_enabled" {
  description = "Key Vault purge protection."
  type        = bool
  default     = true
}

variable "key_vault_soft_delete_days" {
  description = "Key Vault soft-delete retention."
  type        = number
  default     = 7
}

variable "key_vault_allowed_ip_ranges" {
  description = "Optional admin egress IPs for the Key Vault firewall (empty = no public access)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily cap (-1 = none)."
  type        = number
  default     = 2
}

variable "alert_email_addresses" {
  description = "Alert email receivers."
  type        = map(string)
  default     = {}
}

variable "defender_enabled" {
  description = "Microsoft Defender for Containers."
  type        = bool
  default     = false
}

variable "deployment_safeguards_level" {
  description = "null, Warn or Enforce."
  type        = string
  default     = "Warn"
}

variable "jumpbox_enabled" {
  description = "Deploy the administration jumpbox."
  type        = bool
  default     = false
}

variable "jumpbox_bootstrap_ssh_public_key" {
  description = "Throw-away SSH public key required by the VM API (Entra ID login is used; discard the private key)."
  type        = string
  default     = null

  validation {
    condition     = !var.jumpbox_enabled || var.jumpbox_bootstrap_ssh_public_key != null
    error_message = "jumpbox_bootstrap_ssh_public_key is required when jumpbox_enabled = true."
  }
}

variable "bastion_sku" {
  description = "null, Developer or Standard."
  type        = string
  default     = "Developer"
}

variable "resource_lock_level" {
  description = "Lock on the platform resource group."
  type        = string
  default     = null
}
