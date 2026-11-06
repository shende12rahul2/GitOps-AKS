output "ids" {
  description = "Map of key => role assignment ID."
  value       = { for k, v in azurerm_role_assignment.this : k => v.id }
}
