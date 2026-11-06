# Keys must be static strings (e.g. "aks-kubelet-acrpull") so the plan can
# compute for_each even when principal IDs are only known after apply.
resource "azurerm_role_assignment" "this" {
  for_each = var.assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role_definition_name
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  description                      = each.value.description
  condition                        = each.value.condition
  condition_version                = each.value.condition == null ? null : "2.0"
  skip_service_principal_aad_check = each.value.principal_type == "ServicePrincipal"
}
