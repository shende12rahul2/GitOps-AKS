# Terraform owns the shares. Kubernetes consumes them through statically
# provisioned PersistentVolumes (managed by Argo CD), never through dynamic
# provisioning, so the same share is never created twice by two owners.
resource "azurerm_storage_share" "this" {
  for_each = var.shares

  name               = each.key
  storage_account_id = var.storage_account_id
  quota              = each.value.quota_gb
  enabled_protocol   = each.value.protocol
  access_tier        = each.value.protocol == "SMB" ? each.value.access_tier : null

  metadata = {
    owner   = "terraform"
    purpose = each.value.purpose
  }
}

resource "azurerm_monitor_metric_alert" "capacity" {
  for_each = var.alerts_enabled ? var.shares : {}

  name                = "alert-share-${each.key}-capacity"
  resource_group_name = var.resource_group_name
  scopes              = ["${var.storage_account_id}/fileServices/default"]
  description         = "File share ${each.key} above ${var.capacity_alert_percent}% of its ${each.value.quota_gb} GiB quota."
  severity            = 2
  frequency           = "PT1H"
  window_size         = "PT6H"

  criteria {
    metric_namespace       = "Microsoft.Storage/storageAccounts/fileServices"
    metric_name            = "FileCapacity"
    aggregation            = "Average"
    operator               = "GreaterThan"
    threshold              = each.value.quota_gb * 1073741824 * var.capacity_alert_percent / 100
    skip_metric_validation = true

    dimension {
      name     = "FileShare"
      operator = "Include"
      values   = [each.key]
    }
  }

  action {
    action_group_id = var.action_group_id
  }
}
