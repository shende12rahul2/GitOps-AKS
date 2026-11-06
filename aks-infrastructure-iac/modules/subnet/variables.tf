variable "name" {
  description = "Subnet name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the parent VNet."
  type        = string
}

variable "virtual_network_name" {
  description = "Parent VNet name."
  type        = string
}

variable "address_prefixes" {
  description = "Subnet CIDR prefixes."
  type        = list(string)

  validation {
    condition     = length(var.address_prefixes) > 0 && alltrue([for c in var.address_prefixes : can(cidrhost(c, 0))])
    error_message = "address_prefixes must contain valid CIDRs."
  }
}

variable "private_endpoint_network_policies" {
  description = "Enabled, Disabled, NetworkSecurityGroupEnabled or RouteTableEnabled. Use Enabled on private endpoint subnets so NSGs apply to PE traffic."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], var.private_endpoint_network_policies)
    error_message = "Invalid private_endpoint_network_policies value."
  }
}

variable "delegation" {
  description = "Optional service delegation (e.g. Microsoft.DBforPostgreSQL/flexibleServers or Microsoft.Network/applicationGateways)."
  type = object({
    name         = string
    service_name = string
    actions      = optional(list(string), [])
  })
  default = null
}

# Wrapped in objects on purpose: `var.x == null` on a known object is known at
# plan time even when the ID inside is not yet known (created in the same apply).
variable "network_security_group" {
  description = "Optional NSG to associate: { id = <nsg id> }."
  type        = object({ id = string })
  default     = null
}

variable "route_table" {
  description = "Optional route table to associate (e.g. UDR to Azure Firewall in production): { id = <route table id> }."
  type        = object({ id = string })
  default     = null
}

variable "nat_gateway" {
  description = "Optional NAT Gateway for deterministic egress: { id = <nat gateway id> }."
  type        = object({ id = string })
  default     = null
}
