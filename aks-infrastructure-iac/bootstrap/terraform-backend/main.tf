data "azurerm_client_config" "current" {}

locals {
  name_prefix = "${var.project}-tfstate-${var.location_short}"
  suffix      = substr(sha1("${var.subscription_id}/${var.project}/tfstate"), 0, 6)
  tags = {
    project    = var.project
    managed_by = "terraform"
    repository = "aks-infrastructure-iac"
    layer      = "bootstrap"
    owner      = var.owner
  }

  github_oidc_issuer = "https://token.actions.githubusercontent.com"
  infra_repo         = "${var.github_organization}/${var.infrastructure_repository}"

  # Roles the Terraform apply identity may delegate. Constrained delegation stops
  # the pipeline from granting itself (or anyone) Owner / User Access Administrator.
  delegable_roles = [
    "AcrPull",
    "AcrPush",
    "Key Vault Secrets User",
    "Key Vault Secrets Officer",
    "Key Vault Reader",
    "Network Contributor",
    "Managed Identity Operator",
    "Contributor",
    "Reader",
    "Monitoring Reader",
    "Monitoring Metrics Publisher",
    "Storage File Data SMB MI Admin",
    "Storage File Data Privileged Reader",
    "Storage File Data SMB Share Reader",
    "Azure Kubernetes Service Cluster User Role",
    "Azure Kubernetes Service RBAC Reader",
    "Azure Kubernetes Service RBAC Writer",
    "Azure Kubernetes Service RBAC Admin",
    "Azure Kubernetes Service RBAC Cluster Admin",
    "Log Analytics Reader",
    "Virtual Machine Administrator Login",
  ]
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  name                     = substr("st${replace(var.project, "-", "")}tfstate${local.suffix}", 0, 24)
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.state_replication_type
  access_tier              = "Hot"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  # Entra ID only. No account keys or SAS tokens can read the state.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false

  # GitHub-hosted runners use the public endpoint, protected by Entra RBAC.
  # Restrict to known egress IPs (allowed_ip_ranges) or move to a private
  # endpoint with self-hosted runners for production.
  public_network_access = "Enabled"

  network_rules {
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
  }

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    change_feed_retention_in_days = 90
    last_access_time_enabled      = false

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }

    # Point-in-time restore of block blobs (requires versioning + change feed).
    restore_policy {
      days = 29
    }
  }

  tags = local.tags
}

# One container per environment: RBAC is scoped per container, so the dev
# pipeline identity cannot read or lock production state.
resource "azurerm_storage_container" "state" {
  for_each = toset(var.environments)

  name                  = "tfstate-${each.value}"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "bootstrap" {
  name                  = "tfstate-bootstrap"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "state" {
  name       = "lock-tfstate"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Terraform remote state. Deleting this account destroys the record of all environments."
}

# --- GitHub Actions identities (OIDC, no secrets) ------------------------------
# plan:  pull requests; read-only on Azure, can lock/read state.
# apply: GitHub environment "<env>" (protected, required reviewers).
resource "azurerm_user_assigned_identity" "github" {
  for_each = {
    for pair in setproduct(var.environments, ["plan", "apply"]) :
    "${pair[0]}-${pair[1]}" => { env = pair[0], kind = pair[1] }
  }

  name                = "id-${var.project}-github-tf-${each.key}"
  location            = azurerm_resource_group.state.location
  resource_group_name = azurerm_resource_group.state.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "plan_pr" {
  for_each = toset(var.environments)

  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.github["${each.value}-plan"].id
  issuer                    = local.github_oidc_issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${local.infra_repo}:pull_request"
}

resource "azurerm_federated_identity_credential" "plan_env" {
  for_each = toset(var.environments)

  # Plans that run inside the "<env>-plan" GitHub environment (e.g. drift checks on main).
  name                      = "github-env-${each.value}-plan"
  user_assigned_identity_id = azurerm_user_assigned_identity.github["${each.value}-plan"].id
  issuer                    = local.github_oidc_issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${local.infra_repo}:environment:${each.value}-plan"
}

resource "azurerm_federated_identity_credential" "apply" {
  for_each = toset(var.environments)

  name                      = "github-env-${each.value}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github["${each.value}-apply"].id
  issuer                    = local.github_oidc_issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${local.infra_repo}:environment:${each.value}"
}

data "azurerm_role_definition" "delegable" {
  for_each = toset(local.delegable_roles)

  name  = each.value
  scope = "/subscriptions/${var.subscription_id}"
}

locals {
  delegable_role_guids = join(", ", sort([for r in data.azurerm_role_definition.delegable : basename(r.role_definition_id)]))

  # ABAC condition: role assignment writes/deletes are allowed only for the roles above.
  rbac_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_role_guids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_role_guids}}
     )
    )
  EOT
}

resource "azurerm_role_assignment" "plan_reader" {
  for_each = toset(var.environments)

  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github["${each.value}-plan"].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Terraform plan (${each.value}): read Azure resources."
}

resource "azurerm_role_assignment" "plan_state" {
  for_each = toset(var.environments)

  # Plans take a blob lease (state lock), so they need write on their container.
  scope                = azurerm_storage_container.state[each.value].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github["${each.value}-plan"].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Terraform plan (${each.value}): read and lock state."
}

resource "azurerm_role_assignment" "apply_contributor" {
  for_each = toset(var.environments)

  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github["${each.value}-apply"].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Terraform apply (${each.value}): manage resources."
}

resource "azurerm_role_assignment" "apply_rbac" {
  for_each = toset(var.environments)

  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github["${each.value}-apply"].principal_id
  principal_type       = "ServicePrincipal"
  condition            = local.rbac_condition
  condition_version    = "2.0"
  description          = "Terraform apply (${each.value}): assign only an allow-listed set of roles."
}

resource "azurerm_role_assignment" "apply_state" {
  for_each = toset(var.environments)

  scope                = azurerm_storage_container.state[each.value].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github["${each.value}-apply"].principal_id
  principal_type       = "ServicePrincipal"
  description          = "Terraform apply (${each.value}): read/write state."
}

resource "azurerm_role_assignment" "admins_state" {
  for_each = toset(var.environments)

  scope                = azurerm_storage_container.state[each.value].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.platform_admins_group_object_id
  principal_type       = "Group"
  description          = "Platform administrators: state recovery (${each.value})."
}
