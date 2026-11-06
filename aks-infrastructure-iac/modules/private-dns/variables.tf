variable "resource_group_name" {
  description = "Resource group that owns the private DNS zones (normally the network resource group)."
  type        = string
}

variable "zone_names" {
  description = "Private DNS zone names, e.g. privatelink.vaultcore.azure.net."
  type        = list(string)

  validation {
    condition     = length(var.zone_names) == length(distinct(var.zone_names))
    error_message = "zone_names must be unique."
  }
}

variable "virtual_network_ids" {
  description = "Map of short key => VNet ID to link every zone to."
  type        = map(string)
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
