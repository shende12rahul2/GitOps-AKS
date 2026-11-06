output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace name."
  value       = azurerm_log_analytics_workspace.this.name
}

output "monitor_workspace_id" {
  description = "Azure Monitor workspace ID (null when Prometheus is disabled)."
  value       = try(azurerm_monitor_workspace.this[0].id, null)
}

output "action_group_id" {
  description = "Critical alert action group ID."
  value       = azurerm_monitor_action_group.this.id
}
