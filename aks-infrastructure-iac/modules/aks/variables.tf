variable "name" {
  description = "AKS cluster name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the cluster resource."
  type        = string
}

variable "node_resource_group_name" {
  description = "Name of the AKS-managed node resource group (MC_ group)."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the private API server FQDN."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes minor version alias (e.g. "1.36"). AKS resolves the alias to the
    latest supported patch, and automatic_upgrade_channel = "patch" keeps it there.
    Check support with: az aks get-versions -l <region> -o table
  EOT
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Use a minor alias such as 1.36 (patch versions are managed by the upgrade channel)."
  }
}

variable "sku_tier" {
  description = "Free (no API server SLA, POC) or Standard (financially backed SLA, production)."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "private_dns_zone_id" {
  description = "\"System\" (AKS-managed zone) or the ID of a custom privatelink.<region>.azmk8s.io zone."
  type        = string
  default     = "System"
}

variable "admin_group_object_ids" {
  description = "Entra group object IDs granted cluster-admin (platform administrators)."
  type        = list(string)

  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "At least one admin group is required because local accounts are disabled."
  }
}

variable "control_plane_identity_id" {
  description = "User-assigned identity ID for the AKS control plane (needs Network Contributor on the node subnet and Managed Identity Operator on the kubelet identity)."
  type        = string
}

variable "kubelet_identity" {
  description = "Pre-created kubelet identity (AcrPull, Azure Files mount)."
  type = object({
    id           = string
    client_id    = string
    principal_id = string
  })
}

variable "automatic_upgrade_channel" {
  description = "patch (recommended), stable, rapid, node-image or none."
  type        = string
  default     = "patch"

  validation {
    condition     = contains(["patch", "stable", "rapid", "node-image", "none"], var.automatic_upgrade_channel)
    error_message = "Invalid upgrade channel."
  }
}

variable "maintenance_day" {
  description = "Day of week for planned maintenance."
  type        = string
  default     = "Sunday"
}

variable "maintenance_start_time" {
  description = "Maintenance start time (HH:MM, UTC)."
  type        = string
  default     = "02:00"
}

variable "node_subnet_id" {
  description = "Subnet for node NICs (CNI Overlay: pods do not consume VNet IPs)."
  type        = string
}

variable "pod_cidr" {
  description = "Overlay pod CIDR. Must not overlap the VNet, peered networks or service CIDR."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. The DNS service IP is the 10th address."
  type        = string
  default     = "172.16.0.0/16"
}

variable "outbound_type" {
  description = "loadBalancer (POC default), userAssignedNATGateway, or userDefinedRouting (Azure Firewall, production)."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userAssignedNATGateway", "userDefinedRouting", "managedNATGateway"], var.outbound_type)
    error_message = "Invalid outbound_type."
  }
}

variable "nat_gateway_attached" {
  description = "Set true when a NAT Gateway is associated with the node subnet."
  type        = bool
  default     = false
}

variable "system_node_pool" {
  description = "System node pool settings (tainted CriticalAddonsOnly)."
  type = object({
    vm_size         = string
    min_count       = number
    max_count       = number
    max_pods        = optional(number, 110)
    os_disk_type    = optional(string, "Ephemeral")
    os_disk_size_gb = optional(number, 64)
    zones           = optional(list(string))
  })

  validation {
    condition     = var.system_node_pool.min_count >= 1 && var.system_node_pool.max_count >= var.system_node_pool.min_count
    error_message = "System pool needs min_count >= 1 and max_count >= min_count."
  }
}

variable "user_node_pools" {
  description = "Map of user node pools keyed by pool name (lowercase, <= 12 chars)."
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

  validation {
    condition     = alltrue([for k in keys(var.user_node_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "Node pool names must be lowercase alphanumeric, start with a letter and be at most 12 characters."
  }
}

variable "host_encryption_enabled" {
  description = "Encrypt temp disks, caches and OS/data flows at the VM host (no extra cost; requires the Microsoft.Compute/EncryptionAtHost subscription feature, see scripts/register-providers.sh)."
  type        = bool
  default     = true
}

variable "agic_enabled" {
  description = "Enable the Application Gateway Ingress Controller add-on (false = in-cluster ingress controller mode)."
  type        = bool
  default     = true
}

variable "application_gateway_id" {
  description = "Application Gateway ID targeted by AGIC (required when agic_enabled)."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for Container Insights and control-plane logs."
  type        = string
}

variable "container_insights_streams" {
  description = "Container Insights streams to collect (cost profile)."
  type        = list(string)
  default = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
    "Microsoft-KubeNodeInventory",
  ]
}

variable "control_plane_log_categories" {
  description = "AKS resource log categories. kube-audit-admin excludes read events and is much cheaper than kube-audit."
  type        = list(string)
  default     = ["kube-audit-admin", "guard"]
}

variable "prometheus_enabled" {
  description = "Send metrics to managed Prometheus (monitor_workspace_id)."
  type        = bool
  default     = true
}

variable "alerts_enabled" {
  description = "Create Prometheus alert rules routed to action_group_id."
  type        = bool
  default     = true
}

variable "monitor_workspace_id" {
  description = "Azure Monitor workspace ID for managed Prometheus (null = disabled)."
  type        = string
  default     = null
}

variable "action_group_id" {
  description = "Action group for Prometheus alert rules."
  type        = string
  default     = null
}

variable "defender_enabled" {
  description = "Microsoft Defender for Containers sensor (billed per vCore)."
  type        = bool
  default     = false
}

variable "deployment_safeguards_level" {
  description = "AKS Deployment Safeguards: null (off), Warn or Enforce."
  type        = string
  default     = "Warn"

  validation {
    condition     = var.deployment_safeguards_level == null || contains(["Warn", "Enforce"], coalesce(var.deployment_safeguards_level, "x"))
    error_message = "deployment_safeguards_level must be null, Warn or Enforce."
  }
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
