variable "name" {
  description = "Jumpbox VM name."
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

variable "subnet_id" {
  description = "Management subnet for the VM NIC."
  type        = string
}

variable "virtual_network_id" {
  description = "VNet ID (Bastion Developer SKU attaches to the VNet)."
  type        = string
}

variable "vm_size" {
  description = "VM size. B-series is adequate for CLI administration."
  type        = string
  default     = "Standard_B2s"
}

variable "encryption_at_host_enabled" {
  description = "Encryption at host (requires the subscription feature)."
  type        = bool
  default     = false
}

variable "bootstrap_ssh_public_key" {
  description = "Throw-away SSH public key required by the VM API (logins use Entra ID)."
  type        = string
}

variable "admin_group_object_ids" {
  description = "Map of key => Entra group object ID allowed to log in as VM administrators."
  type        = map(string)
}

variable "auto_shutdown_time" {
  description = "Daily shutdown time (HHMM, UTC)."
  type        = string
  default     = "1900"
}

variable "bastion_sku" {
  description = "null (no Bastion), Developer (free, portal SSH only) or Standard (tunnelling for UI access)."
  type        = string
  default     = "Developer"

  validation {
    condition     = var.bastion_sku == null || contains(["Developer", "Standard"], coalesce(var.bastion_sku, "x"))
    error_message = "bastion_sku must be null, Developer or Standard."
  }
}

variable "bastion_subnet_id" {
  description = "AzureBastionSubnet ID (Standard SKU only)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
