resource "azurerm_network_security_group" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Rules are separate resources keyed by name (stable identity with for_each), so
# adding or removing one rule never re-creates the others.
resource "azurerm_network_security_rule" "this" {
  for_each = var.rules

  name                        = each.key
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  description                 = each.value.description

  source_port_range       = "*"
  destination_port_range  = length(each.value.destination_port_ranges) == 1 ? each.value.destination_port_ranges[0] : null
  destination_port_ranges = length(each.value.destination_port_ranges) > 1 ? each.value.destination_port_ranges : null

  source_address_prefix        = length(each.value.source_address_prefixes) == 1 ? each.value.source_address_prefixes[0] : null
  source_address_prefixes      = length(each.value.source_address_prefixes) > 1 ? each.value.source_address_prefixes : null
  destination_address_prefix   = length(each.value.destination_address_prefixes) == 1 ? each.value.destination_address_prefixes[0] : null
  destination_address_prefixes = length(each.value.destination_address_prefixes) > 1 ? each.value.destination_address_prefixes : null
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostics_enabled ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_network_security_group.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
