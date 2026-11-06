resource "azurerm_storage_account" "this" {
  name                     = var.name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  access_tier              = var.account_kind == "StorageV2" ? "Hot" : null

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = var.https_traffic_only_enabled
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  large_file_share_enabled          = var.account_kind == "StorageV2" ? true : null

  # Identity-only access. With smb_oauth_enabled the Azure Files CSI driver mounts
  # SMB shares with a managed identity (Kerberos/SMB OAuth); no account key is used.
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = true
  smb_oauth_enabled               = var.smb_oauth_enabled
  local_user_enabled              = false
  sftp_enabled                    = false

  public_network_access = "Disabled"

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
  }

  share_properties {
    # Share soft delete: recover a deleted share for N days.
    retention_policy {
      days = var.share_soft_delete_days
    }

    smb {
      versions                = ["SMB3.1.1"]
      channel_encryption_type = ["AES-128-GCM", "AES-256-GCM"]
      multichannel_enabled    = var.account_tier == "Premium" ? false : null
    }
  }

  tags = var.tags
}

module "private_endpoint" {
  source   = "../private-endpoint"
  for_each = var.private_endpoints

  name                 = "pe-${var.name}-${each.key}"
  location             = var.location
  resource_group_name  = var.resource_group_name
  subnet_id            = var.private_endpoint_subnet_id
  target_resource_id   = azurerm_storage_account.this.id
  subresource_name     = each.key
  private_dns_zone_ids = [each.value]
  tags                 = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "file" {
  count = var.diagnostics_enabled ? 1 : 0

  name                       = "diag-${var.name}-file"
  target_resource_id         = "${azurerm_storage_account.this.id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    # Transaction logs are billed per GB ingested; keep only writes/deletes by default.
    for_each = toset(var.file_log_categories)

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "Transaction"
  }

  enabled_metric {
    category = "Capacity"
  }
}
