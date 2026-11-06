variable "key_vault_name" {
  description = "Target Key Vault name."
  type        = string
}

variable "key_vault_resource_group_name" {
  description = "Resource group containing the Key Vault (the ARM deployment runs there)."
  type        = string
}

variable "secret_name" {
  description = "Secret name (1-127 alphanumerics and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-zA-Z-]{1,127}$", var.secret_name))
    error_message = "Secret names may contain only alphanumerics and hyphens."
  }
}

variable "value" {
  description = "Secret value. For operator-managed secrets this is only the initial placeholder."
  type        = string
  sensitive   = true
}

variable "content_type" {
  description = "Content type hint, e.g. text/plain, application/x-ssh-key, application/x-connection-string."
  type        = string
  default     = "text/plain"
}

variable "operator_managed" {
  description = "true = Terraform creates a placeholder once and never overwrites the value."
  type        = bool
  default     = false
}

variable "reader_principal_ids" {
  description = "Map of stable key => principal ID granted Key Vault Secrets User on this secret only."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Secret tags."
  type        = map(string)
  default     = {}
}
