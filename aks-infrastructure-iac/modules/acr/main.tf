resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku

  # Entra-only access: no admin user, no anonymous pulls. AKS pulls with the
  # kubelet identity (AcrPull); CI pushes with a GitHub OIDC identity (AcrPush).
  admin_enabled          = false
  anonymous_pull_enabled = false

  # Premium-only features are enabled only when the SKU supports them.
  public_network_access_enabled = var.sku == "Premium" ? var.public_network_access_enabled : true
  network_rule_bypass_option    = "AzureServices"
  data_endpoint_enabled         = var.sku == "Premium"
  quarantine_policy_enabled     = false
  retention_policy_in_days      = var.sku == "Premium" ? var.untagged_retention_days : null
  zone_redundancy_enabled       = var.sku == "Premium" ? var.zone_redundancy_enabled : false
  export_policy_enabled         = var.sku == "Premium" ? false : true

  tags = var.tags

  lifecycle {
    precondition {
      condition     = !var.private_endpoint_enabled || var.sku == "Premium"
      error_message = "ACR private endpoints require the Premium SKU."
    }
  }
}

module "private_endpoint" {
  source = "../private-endpoint"
  count  = var.private_endpoint_enabled ? 1 : 0

  name                 = "pe-${var.name}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  subnet_id            = var.private_endpoint_subnet_id
  target_resource_id   = azurerm_container_registry.this.id
  subresource_name     = "registry"
  private_dns_zone_ids = [var.private_dns_zone_id]
  tags                 = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostics_enabled ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
