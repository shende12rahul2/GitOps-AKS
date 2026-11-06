variable "name" {
  description = "Private endpoint name (pe-<service>-<env>)."
  type        = string
}

variable "location" {
  description = "Azure region (must match the subnet's VNet region)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the private endpoint."
  type        = string
}

variable "subnet_id" {
  description = "Private endpoint subnet ID."
  type        = string
}

variable "target_resource_id" {
  description = "Resource ID of the PaaS resource."
  type        = string
}

variable "subresource_name" {
  description = "Private link group ID, e.g. vault, file, registry, redisEnterprise."
  type        = string
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs for the zone group."
  type        = list(string)

  validation {
    condition     = length(var.private_dns_zone_ids) > 0
    error_message = "At least one private DNS zone is required so clients resolve the private IP."
  }
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
