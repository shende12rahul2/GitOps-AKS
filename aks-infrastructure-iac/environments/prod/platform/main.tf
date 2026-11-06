data "azurerm_client_config" "current" {}

module "naming" {
  source = "../../../modules/naming"

  project         = var.project
  environment     = var.environment
  location_short  = var.location_short
  subscription_id = var.subscription_id
  layer           = "platform"
  owner           = var.owner
  cost_center     = var.cost_center
}

locals {
  names     = module.naming.names
  tags      = module.naming.tags
  tenant_id = data.azurerm_client_config.current.tenant_id

  agic_enabled = var.ingress_mode == "agic"

  # Single private IP that every application/admin hostname resolves to: the
  # App Gateway private frontend (agic) or the in-cluster controller's internal LB.
  appgw_private_ip   = cidrhost(local.foundation.subnet_cidrs.appgw, 10)
  internal_lb_ip     = cidrhost(local.foundation.subnet_cidrs.aks_nodes, 1000)
  ingress_private_ip = local.agic_enabled ? local.appgw_private_ip : local.internal_lb_ip

  # Kubernetes service accounts that receive an Entra workload identity.
  workload_identities = {
    "frontend"             = { namespace = "apps", service_account = "frontend" }
    "user-service"         = { namespace = "apps", service_account = "user-service" }
    "product-service"      = { namespace = "apps", service_account = "product-service" }
    "order-service"        = { namespace = "apps", service_account = "order-service" }
    "notification-service" = { namespace = "apps", service_account = "notification-service" }
    "airflow"              = { namespace = "airflow", service_account = "airflow-kv-sync" }
    "db-bootstrap"         = { namespace = "platform-jobs", service_account = "db-bootstrap" }
  }

  groups = var.entra_group_object_ids
}

module "rg_platform" {
  source = "../../../modules/resource-group"

  name       = local.names.rg_platform
  location   = var.location
  lock_level = var.resource_lock_level
  tags       = local.tags
}

# --- Monitoring -----------------------------------------------------------------
module "monitoring" {
  source = "../../../modules/monitoring"

  location               = var.location
  resource_group_name    = module.rg_platform.name
  log_analytics_name     = local.names.log_analytics
  monitor_workspace_name = local.names.monitor_workspace
  action_group_name      = local.names.action_group
  retention_in_days      = var.log_retention_days
  daily_quota_gb         = var.log_daily_quota_gb
  prometheus_enabled     = true
  alert_email_addresses  = var.alert_email_addresses
  tags                   = local.tags
}

# --- Identities ---------------------------------------------------------------------
module "id_aks_control_plane" {
  source = "../../../modules/managed-identity"

  name                = "${local.names.identity_prefix}-aks-control-plane"
  location            = var.location
  resource_group_name = module.rg_platform.name
  tags                = local.tags
}

module "id_aks_kubelet" {
  source = "../../../modules/managed-identity"

  name                = "${local.names.identity_prefix}-aks-kubelet"
  location            = var.location
  resource_group_name = module.rg_platform.name
  tags                = local.tags
}

module "id_workload" {
  source   = "../../../modules/managed-identity"
  for_each = local.workload_identities

  name                = "${local.names.identity_prefix}-${each.key}"
  location            = var.location
  resource_group_name = module.rg_platform.name
  tags                = local.tags

  federated_credentials = {
    "aks-${each.value.namespace}-${each.value.service_account}" = {
      issuer  = module.aks.oidc_issuer_url
      subject = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
    }
  }
}

# Application CI (aks-microservices-app) pushes images. Separate from the
# infrastructure pipeline identities created by the bootstrap layer.
module "id_github_acr" {
  source = "../../../modules/managed-identity"

  name                = "${local.names.identity_prefix}-github-acr"
  location            = var.location
  resource_group_name = module.rg_platform.name
  tags                = local.tags

  federated_credentials = merge(
    {
      "github-app-env-${var.environment}" = {
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:${var.github_organization}/${var.app_repository}:environment:${var.environment}"
      }
    },
    var.environment == "dev" ? {
      "github-app-main" = {
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:${var.github_organization}/${var.app_repository}:ref:refs/heads/main"
      }
    } : {},
  )
}

# Role assignments AKS needs *before* the cluster can be created (subnet join,
# kubelet identity binding). This is the one justified explicit depends_on.
module "rbac_aks_prerequisites" {
  source = "../../../modules/role-assignment"

  assignments = {
    "aks-cp-network-contributor-nodes" = {
      scope                = local.foundation.subnet_ids["snet-aks-nodes"]
      role_definition_name = "Network Contributor"
      principal_id         = module.id_aks_control_plane.principal_id
      description          = "AKS control plane: join node subnet, manage internal load balancers."
    }
    "aks-cp-mi-operator-kubelet" = {
      scope                = module.id_aks_kubelet.id
      role_definition_name = "Managed Identity Operator"
      principal_id         = module.id_aks_control_plane.principal_id
      description          = "AKS control plane: assign the kubelet identity to node VMSS."
    }
  }
}

# --- Registry and secrets -------------------------------------------------------------
module "acr" {
  source = "../../../modules/acr"

  name                       = local.names.acr
  location                   = var.location
  resource_group_name        = module.rg_platform.name
  sku                        = var.acr_sku
  private_endpoint_enabled   = var.acr_private_endpoint_enabled
  private_endpoint_subnet_id = local.foundation.subnet_ids["snet-private-endpoints"]
  private_dns_zone_id        = try(local.foundation.private_dns_zone_ids["privatelink.azurecr.io"], null)
  diagnostics_enabled        = true
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

module "key_vault" {
  source = "../../../modules/key-vault"

  name                          = local.names.key_vault
  location                      = var.location
  resource_group_name           = module.rg_platform.name
  tenant_id                     = local.tenant_id
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  soft_delete_retention_days    = var.key_vault_soft_delete_days
  public_network_access_enabled = length(var.key_vault_allowed_ip_ranges) > 0
  allowed_ip_ranges             = var.key_vault_allowed_ip_ranges
  private_endpoint_subnet_id    = local.foundation.subnet_ids["snet-private-endpoints"]
  private_dns_zone_id           = local.foundation.private_dns_zone_ids["privatelink.vaultcore.azure.net"]
  diagnostics_enabled           = true
  log_analytics_workspace_id    = module.monitoring.log_analytics_workspace_id
  tags                          = local.tags
}

# --- Ingress: Application Gateway (AGIC mode only) -------------------------------------
module "app_gateway" {
  source = "../../../modules/application-gateway"
  count  = local.agic_enabled ? 1 : 0

  name                       = local.names.app_gateway
  location                   = var.location
  resource_group_name        = module.rg_platform.name
  sku                        = var.appgw_sku
  subnet_id                  = local.foundation.subnet_ids["snet-appgw"]
  private_ip_address         = local.appgw_private_ip
  public_frontend_enabled    = local.foundation.appgw_public_frontend_enabled
  zones                      = var.appgw_zones
  min_capacity               = var.appgw_min_capacity
  max_capacity               = var.appgw_max_capacity
  waf_mode                   = var.appgw_waf_mode
  diagnostics_enabled        = true
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = local.tags
}

# --- AKS ---------------------------------------------------------------------------
module "aks" {
  source = "../../../modules/aks"

  name                      = local.names.aks
  location                  = var.location
  resource_group_name       = module.rg_platform.name
  node_resource_group_name  = local.names.rg_aks_nodes
  dns_prefix                = local.names.aks
  tenant_id                 = local.tenant_id
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = var.aks_sku_tier
  admin_group_object_ids    = [local.groups.platform_admins]
  control_plane_identity_id = module.id_aks_control_plane.id
  kubelet_identity = {
    id           = module.id_aks_kubelet.id
    client_id    = module.id_aks_kubelet.client_id
    principal_id = module.id_aks_kubelet.principal_id
  }

  node_subnet_id       = local.foundation.subnet_ids["snet-aks-nodes"]
  outbound_type        = local.foundation.nat_gateway_enabled ? "userAssignedNATGateway" : "loadBalancer"
  nat_gateway_attached = local.foundation.nat_gateway_enabled
  system_node_pool     = var.system_node_pool
  user_node_pools      = var.user_node_pools

  agic_enabled           = local.agic_enabled
  application_gateway_id = local.agic_enabled ? module.app_gateway[0].id : null

  log_analytics_workspace_id  = module.monitoring.log_analytics_workspace_id
  prometheus_enabled          = true
  monitor_workspace_id        = module.monitoring.monitor_workspace_id
  alerts_enabled              = true
  action_group_id             = module.monitoring.action_group_id
  defender_enabled            = var.defender_enabled
  deployment_safeguards_level = var.deployment_safeguards_level
  tags                        = local.tags

  depends_on = [module.rbac_aks_prerequisites]
}

module "rbac_platform_workloads" {
  source = "../../../modules/role-assignment"

  assignments = merge(
    {
      "kubelet-acr-pull" = {
        scope                = module.acr.id
        role_definition_name = "AcrPull"
        principal_id         = module.id_aks_kubelet.principal_id
        description          = "Nodes pull images from ACR."
      }
      "github-acr-push" = {
        scope                = module.acr.id
        role_definition_name = "AcrPush"
        principal_id         = module.id_github_acr.principal_id
        description          = "Application CI pushes images (OIDC)."
      }
    },
    var.promotion_source_acr_id == null ? {} : {
      "github-acr-pull-promotion-source" = {
        scope                = var.promotion_source_acr_id
        role_definition_name = "AcrPull"
        principal_id         = module.id_github_acr.principal_id
        description          = "Promotion: copy digests from the lower-environment registry."
      }
    },
    local.agic_enabled ? {
      "agic-appgw-contributor" = {
        scope                = module.app_gateway[0].id
        role_definition_name = "Contributor"
        principal_id         = module.aks.agic_identity_object_id
        description          = "AGIC reconciles listeners, rules and pools on the gateway."
      }
      "agic-rg-reader" = {
        scope                = module.rg_platform.id
        role_definition_name = "Reader"
        principal_id         = module.aks.agic_identity_object_id
        description          = "AGIC reads the gateway resource group."
      }
      "agic-subnet-network-contributor" = {
        scope                = local.foundation.subnet_ids["snet-appgw"]
        role_definition_name = "Network Contributor"
        principal_id         = module.aks.agic_identity_object_id
        description          = "AGIC joins the gateway subnet."
      }
    } : {},
  )
}

# --- Private DNS records for the single ingress entry point ------------------------------
resource "azurerm_private_dns_a_record" "ingress" {
  for_each = toset(var.ingress_hostnames)

  name                = each.value
  private_dns_zone_id = local.foundation.private_dns_zone_ids[local.foundation.app_dns_zone_name]
  ttl                 = 300
  records             = [local.ingress_private_ip]
  tags                = local.tags
}

# --- Optional administration jumpbox --------------------------------------------------------
module "jumpbox" {
  source = "../../../modules/jumpbox"
  count  = var.jumpbox_enabled ? 1 : 0

  name                     = local.names.jumpbox
  location                 = var.location
  resource_group_name      = module.rg_platform.name
  subnet_id                = local.foundation.subnet_ids["snet-mgmt"]
  virtual_network_id       = local.foundation.vnet_id
  bootstrap_ssh_public_key = var.jumpbox_bootstrap_ssh_public_key
  admin_group_object_ids   = { platform_admins = local.groups.platform_admins, devops = local.groups.devops }
  bastion_sku              = var.bastion_sku
  bastion_subnet_id        = try(local.foundation.subnet_ids["AzureBastionSubnet"], null)
  tags                     = local.tags
}
