variable "assignments" {
  description = "Map of stable key => role assignment definition."
  type = map(object({
    scope                = string
    role_definition_name = string
    principal_id         = string
    principal_type       = optional(string, "ServicePrincipal")
    description          = optional(string)
    condition            = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.assignments) : contains(["User", "Group", "ServicePrincipal"], a.principal_type)])
    error_message = "principal_type must be User, Group or ServicePrincipal (managed identities are ServicePrincipal)."
  }

  validation {
    condition     = alltrue([for a in values(var.assignments) : !contains(["Owner", "User Access Administrator"], a.role_definition_name)])
    error_message = "Owner and User Access Administrator must not be granted from this module; use a reviewed, out-of-band process."
  }
}
