resource "azurerm_subnet" "this" {
  name                 = var.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.virtual_network_name
  address_prefixes     = var.address_prefixes

  # Azure is retiring implicit "default outbound access". Every subnet in this
  # design either has explicit egress (AKS Standard LB / NAT Gateway) or needs none.
  default_outbound_access_enabled = false

  private_endpoint_network_policies = var.private_endpoint_network_policies

  dynamic "delegation" {
    for_each = var.delegation == null ? [] : [var.delegation]

    content {
      name = delegation.value.name

      service_delegation {
        name    = delegation.value.service_name
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  count = var.network_security_group == null ? 0 : 1

  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = var.network_security_group.id
}

resource "azurerm_subnet_route_table_association" "this" {
  count = var.route_table == null ? 0 : 1

  subnet_id      = azurerm_subnet.this.id
  route_table_id = var.route_table.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  count = var.nat_gateway == null ? 0 : 1

  subnet_id      = azurerm_subnet.this.id
  nat_gateway_id = var.nat_gateway.id
}
