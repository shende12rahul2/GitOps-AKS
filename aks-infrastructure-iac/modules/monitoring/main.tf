resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  daily_quota_gb      = var.daily_quota_gb

  # Workspace keys are not needed: AKS (oms_agent with msi_auth) and diagnostic
  # settings use managed identities / ARM. Disabling local auth removes a shared secret.
  local_authentication_enabled = false

  tags = var.tags
}

# Azure Monitor workspace = managed Prometheus metrics store (AKS monitor_metrics).
resource "azurerm_monitor_workspace" "this" {
  count = var.prometheus_enabled ? 1 : 0

  name                = var.monitor_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = substr(replace(var.action_group_name, "-", ""), 0, 12)
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses

    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}
