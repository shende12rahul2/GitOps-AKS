variable "name" {
  description = "Identity name (id-<project>-<env>-<workload>)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the identity."
  type        = string
}

variable "federated_credentials" {
  description = <<-EOT
    Map of credential name => { issuer, subject, audience }.
    AKS workload identity: issuer = AKS OIDC issuer URL, subject = system:serviceaccount:<ns>:<sa>.
    GitHub OIDC: issuer = https://token.actions.githubusercontent.com, subject = repo:<org>/<repo>:environment:<env>.
  EOT
  type = map(object({
    issuer   = string
    subject  = string
    audience = optional(list(string), ["api://AzureADTokenExchange"])
  }))
  default = {}

  validation {
    condition     = length(var.federated_credentials) <= 20
    error_message = "A user-assigned identity supports at most 20 federated credentials."
  }

  validation {
    condition     = alltrue([for k in keys(var.federated_credentials) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{2,119}$", k))])
    error_message = "Federated credential names must be 3-120 chars: letters, digits, '-' or '_'."
  }
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
