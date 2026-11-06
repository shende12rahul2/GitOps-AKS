variable "name" {
  description = "NSG name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "rules" {
  description = <<-EOT
    Map of security rules keyed by rule name. Azure default rules (AllowVnetInBound,
    AllowAzureLoadBalancerInBound, DenyAllInBound, ...) still apply below priority 4096.
  EOT
  type = map(object({
    priority                     = number
    direction                    = string
    access                       = string
    protocol                     = string
    source_address_prefixes      = list(string)
    destination_address_prefixes = list(string)
    destination_port_ranges      = list(string)
    description                  = optional(string, "")
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.rules) :
      r.priority >= 100 && r.priority <= 4096 &&
      contains(["Inbound", "Outbound"], r.direction) &&
      contains(["Allow", "Deny"], r.access) &&
      contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], r.protocol) &&
      length(r.source_address_prefixes) > 0 &&
      length(r.destination_address_prefixes) > 0 &&
      length(r.destination_port_ranges) > 0
    ])
    error_message = "Each rule needs priority 100-4096, a valid direction/access/protocol and non-empty prefixes and ports."
  }
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for NSG event logs (used when diagnostics_enabled = true)."
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
