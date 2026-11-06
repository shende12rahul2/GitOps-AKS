resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Federated credentials let a Kubernetes service account (AKS OIDC issuer) or a
# GitHub Actions job (token.actions.githubusercontent.com) exchange its own token
# for an Entra token for this identity. No client secrets exist anywhere.
resource "azurerm_federated_identity_credential" "this" {
  for_each = var.federated_credentials

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  audience                  = each.value.audience
  issuer                    = each.value.issuer
  subject                   = each.value.subject
}
