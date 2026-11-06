variable "project" {
  description = "Short project code (lowercase, 3-8 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,7}$", var.project))
    error_message = "project must be 3-8 lowercase alphanumerics starting with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "location_short" {
  description = "Short region code, e.g. eus2."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_short))
    error_message = "location_short must be 2-6 lowercase alphanumerics."
  }
}

variable "subscription_id" {
  description = "Subscription ID (seed for the deterministic uniqueness suffix)."
  type        = string
}

variable "layer" {
  description = "Lifecycle layer (foundation, platform, data)."
  type        = string
}

variable "owner" {
  description = "Owning team or contact."
  type        = string
}

variable "cost_center" {
  description = "Cost center for chargeback."
  type        = string
}

variable "extra_tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
