resource "azurerm_private_dns_zone" "this" {
  for_each = toset(var.zone_names)

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

locals {
  # One link per (zone, vnet) pair, keyed for stable identity.
  links = {
    for pair in setproduct(var.zone_names, keys(var.virtual_network_ids)) :
    "${pair[0]}|${pair[1]}" => {
      zone     = pair[0]
      vnet_key = pair[1]
    }
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.links

  name                 = "link-${each.value.vnet_key}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.value.zone].id
  virtual_network_id   = var.virtual_network_ids[each.value.vnet_key]
  registration_enabled = false
  tags                 = var.tags
}
