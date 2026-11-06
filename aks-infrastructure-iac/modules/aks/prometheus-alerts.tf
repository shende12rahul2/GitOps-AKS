# Prometheus alert rules (managed Prometheus). Kept in a separate file because
# Checkov's HCL parser rejects the valid `for` attribute; .checkov.yaml skips
# only this file, so every security check still runs against main.tf.
resource "azurerm_monitor_alert_prometheus_rule_group" "critical" {
  count = var.prometheus_enabled && var.alerts_enabled ? 1 : 0

  name                = "prom-critical-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kubernetes_cluster.this.name
  scopes              = [var.monitor_workspace_id, azurerm_kubernetes_cluster.this.id]
  interval            = "PT1M"
  rule_group_enabled  = true
  description         = "Critical Kubernetes alerts for ${var.name}"
  tags                = var.tags

  rule {
    alert      = "KubePodCrashLooping"
    expression = "max_over_time(kube_pod_container_status_waiting_reason{reason=\"CrashLoopBackOff\", job=\"kube-state-metrics\"}[5m]) >= 1"
    for        = "PT10M"
    severity   = 2
    enabled    = true
    annotations = {
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping."
    }
    action {
      action_group_id = var.action_group_id
    }
    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT10M"
    }
  }

  rule {
    alert      = "KubeNodeNotReady"
    expression = "kube_node_status_condition{job=\"kube-state-metrics\",condition=\"Ready\",status=\"true\"} == 0"
    for        = "PT15M"
    severity   = 1
    enabled    = true
    annotations = {
      description = "Node {{ $labels.node }} has been NotReady for 15 minutes."
    }
    action {
      action_group_id = var.action_group_id
    }
    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT10M"
    }
  }

  rule {
    alert      = "KubePVCUsageHigh"
    expression = "kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.8"
    for        = "PT15M"
    severity   = 2
    enabled    = true
    annotations = {
      description = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is over 80% full."
    }
    action {
      action_group_id = var.action_group_id
    }
    alert_resolution {
      auto_resolved   = true
      time_to_resolve = "PT10M"
    }
  }
}
