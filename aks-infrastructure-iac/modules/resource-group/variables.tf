variable "name" {
  description = "Resource group name (e.g. rg-akspoc-dev-eus2-network)."
  type        = string

  validation {
    condition     = can(regex("^rg-[a-z0-9-]{3,85}$", var.name))
    error_message = "Resource group names must start with 'rg-' and contain only lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to the resource group."
  type        = map(string)
  default     = {}
}

variable "lock_level" {
  description = "Optional management lock: null (no lock), CanNotDelete or ReadOnly."
  type        = string
  default     = null

  validation {
    condition     = var.lock_level == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock_level, "x"))
    error_message = "lock_level must be null, CanNotDelete or ReadOnly."
  }
}
