# Writes a Key Vault secret through the Azure Resource Manager control plane
# (Microsoft.KeyVault/vaults/secrets) instead of the Key Vault data plane.
#
# Why: the vault has public network access disabled. GitHub-hosted runners cannot
# reach its private endpoint, but ARM (management.azure.com) can always create
# secrets for a caller holding Microsoft.KeyVault/vaults/secrets/write. The value
# is passed as an ARM `securestring` parameter, so it is not persisted in the ARM
# deployment history. It IS stored in Terraform state, which is why the state
# account is Entra-only, private-container, versioned and access-restricted.
locals {
  template = {
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      vaultName   = { type = "string" }
      secretName  = { type = "string" }
      secretValue = { type = "securestring" }
      contentType = { type = "string" }
      tags        = { type = "object" }
    }
    resources = [
      {
        type       = "Microsoft.KeyVault/vaults/secrets"
        apiVersion = "2023-07-01"
        name       = "[format('{0}/{1}', parameters('vaultName'), parameters('secretName'))]"
        tags       = "[parameters('tags')]"
        properties = {
          value       = "[parameters('secretValue')]"
          contentType = "[parameters('contentType')]"
          attributes  = { enabled = true }
        }
      }
    ]
    outputs = {
      secretId = {
        type  = "string"
        value = "[resourceId('Microsoft.KeyVault/vaults/secrets', parameters('vaultName'), parameters('secretName'))]"
      }
      secretUri = {
        type  = "string"
        value = "[reference(resourceId('Microsoft.KeyVault/vaults/secrets', parameters('vaultName'), parameters('secretName')), '2023-07-01').secretUri]"
      }
    }
  }
}

locals {
  parameters = jsonencode({
    vaultName   = { value = var.key_vault_name }
    secretName  = { value = var.secret_name }
    secretValue = { value = var.value }
    contentType = { value = var.content_type }
    tags        = { value = var.tags }
  })

  deployment = var.operator_managed ? azurerm_resource_group_template_deployment.placeholder[0] : azurerm_resource_group_template_deployment.managed[0]
  outputs    = jsondecode(local.deployment.output_content)
}

# Terraform owns the value (generated passwords, connection strings).
resource "azurerm_resource_group_template_deployment" "managed" {
  count = var.operator_managed ? 0 : 1

  name                = "kvsecret-${var.secret_name}"
  resource_group_name = var.key_vault_resource_group_name
  deployment_mode     = "Incremental"
  template_content    = jsonencode(local.template)
  parameters_content  = local.parameters
}

# An operator owns the value (SSH deploy keys, OAuth client secrets). Terraform
# creates a placeholder once so RBAC can be scoped to the secret, then ignores it.
resource "azurerm_resource_group_template_deployment" "placeholder" {
  count = var.operator_managed ? 1 : 0

  name                = "kvsecret-${var.secret_name}"
  resource_group_name = var.key_vault_resource_group_name
  deployment_mode     = "Incremental"
  template_content    = jsonencode(local.template)
  parameters_content  = local.parameters

  lifecycle {
    ignore_changes = [parameters_content, template_content]
  }
}

# Secret-scoped RBAC: each workload identity can read only the secrets it needs.
resource "azurerm_role_assignment" "reader" {
  for_each = var.reader_principal_ids

  scope                            = local.outputs.secretId.value
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = each.value
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Read ${var.secret_name} (${each.key})"
}
