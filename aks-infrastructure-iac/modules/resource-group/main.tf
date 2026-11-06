resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = var.tags
}

# Optional delete lock. Protects long-lived groups (state, networking, data) from
# accidental `terraform destroy` or portal deletion. Must be removed deliberately.
resource "azurerm_management_lock" "this" {
  count = var.lock_level == null ? 0 : 1

  name       = "lock-${var.name}"
  scope      = azurerm_resource_group.this.id
  lock_level = var.lock_level
  notes      = "Managed by Terraform. Remove intentionally before destructive changes."
}
