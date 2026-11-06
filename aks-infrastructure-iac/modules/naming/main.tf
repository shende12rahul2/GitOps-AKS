# Pure naming/tagging module (no resources). Every layer calls it with the same
# inputs, so names are consistent without passing them through remote state.
#
# Pattern: <abbreviation>-<project>-<environment>-<region>[-<purpose>]
# Globally unique names (storage, ACR, Key Vault, PostgreSQL, Redis) get a short
# deterministic suffix derived from the subscription, so they are stable across
# runs without a random resource in state.
locals {
  prefix = "${var.project}-${var.environment}-${var.location_short}"
  flat   = replace(local.prefix, "-", "")
  suffix = substr(sha1("${var.subscription_id}/${var.project}/${var.environment}"), 0, 4)

  names = {
    rg_network        = "rg-${local.prefix}-network"
    rg_platform       = "rg-${local.prefix}-platform"
    rg_data           = "rg-${local.prefix}-data"
    rg_aks_nodes      = "rg-${local.prefix}-aks-nodes"
    vnet              = "vnet-${local.prefix}"
    nat_gateway       = "ng-${local.prefix}"
    aks               = "aks-${local.prefix}"
    acr               = substr("acr${local.flat}${local.suffix}", 0, 50)
    key_vault         = substr("kv-${local.prefix}-${local.suffix}", 0, 24)
    app_gateway       = "agw-${local.prefix}"
    log_analytics     = "log-${local.prefix}"
    monitor_workspace = "amw-${local.prefix}"
    action_group      = "ag-${local.prefix}-critical"
    postgresql        = "psql-${local.prefix}-${local.suffix}"
    redis             = "redis-${local.prefix}-${local.suffix}"
    storage_files     = substr("st${local.flat}${local.suffix}", 0, 24)
    jumpbox           = "vm-${local.prefix}-jump"
    postgres_dns_zone = "${local.prefix}.private.postgres.database.azure.com"
    identity_prefix   = "id-${local.prefix}"
  }

  tags = merge(
    {
      project     = var.project
      environment = var.environment
      managed_by  = "terraform"
      repository  = "aks-infrastructure-iac"
      layer       = var.layer
      owner       = var.owner
      cost_center = var.cost_center
    },
    var.extra_tags,
  )
}
