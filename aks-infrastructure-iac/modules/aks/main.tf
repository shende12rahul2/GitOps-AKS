resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = var.node_resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  support_plan        = "KubernetesOfficial"

  # --- API server: private only -------------------------------------------
  # The API server gets a private IP in the cluster VNet. With the "System" zone,
  # AKS creates and links privatelink.<region>.azmk8s.io for the cluster VNet.
  # Use a custom zone ID for hub/spoke so other VNets can resolve it.
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  private_dns_zone_id                 = var.private_dns_zone_id
  run_command_enabled                 = true # `az aks command invoke` break-glass path

  # --- Identity and authorization -----------------------------------------
  local_account_disabled            = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity_id]
  }

  kubelet_identity {
    user_assigned_identity_id = var.kubelet_identity.id
    client_id                 = var.kubelet_identity.client_id
    object_id                 = var.kubelet_identity.principal_id
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # --- Upgrades -------------------------------------------------------------
  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = "NodeImage"

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = var.maintenance_day
    start_time  = var.maintenance_start_time
    utc_offset  = "+00:00"
    duration    = 4
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = var.maintenance_day
    start_time  = var.maintenance_start_time
    utc_offset  = "+00:00"
    duration    = 4
  }

  # --- System node pool -----------------------------------------------------
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool.vm_size
    vnet_subnet_id               = var.node_subnet_id
    orchestrator_version         = var.kubernetes_version
    auto_scaling_enabled         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    max_pods                     = var.system_node_pool.max_pods
    os_sku                       = "Ubuntu"
    os_disk_type                 = var.system_node_pool.os_disk_type
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    only_critical_addons_enabled = true # taints CriticalAddonsOnly=true:NoSchedule
    zones                        = var.system_node_pool.zones
    temporary_name_for_rotation  = "systemtmp"
    host_encryption_enabled      = var.host_encryption_enabled
    node_labels                  = { "workload-class" = "system" }

    upgrade_settings {
      max_surge                     = "1"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 0
    }
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  auto_scaler_profile {
    balance_similar_node_groups      = true
    expander                         = "least-waste"
    scale_down_unneeded              = "10m"
    scale_down_delay_after_add       = "10m"
    skip_nodes_with_local_storage    = false
    scale_down_utilization_threshold = "0.5"
  }

  # --- Networking: Azure CNI Overlay powered by Cilium -----------------------
  # Nodes take VNet IPs; pods take IPs from a private overlay CIDR that never
  # consumes VNet space. Cilium (eBPF) enforces Kubernetes NetworkPolicy.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
    load_balancer_sku   = "standard"
    outbound_type       = var.outbound_type
  }

  # --- Add-ons ----------------------------------------------------------------
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  storage_profile {
    disk_driver_enabled         = true
    file_driver_enabled         = true
    blob_driver_enabled         = false
    snapshot_controller_enabled = true
  }

  dynamic "ingress_application_gateway" {
    for_each = var.agic_enabled ? [var.application_gateway_id] : []

    content {
      gateway_id = ingress_application_gateway.value
    }
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  dynamic "monitor_metrics" {
    for_each = var.prometheus_enabled ? [1] : []

    content {}
  }

  dynamic "microsoft_defender" {
    for_each = var.defender_enabled ? [1] : []

    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  azure_policy_enabled         = true
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 168

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # Managed by the cluster autoscaler.
      default_node_pool[0].node_count,
    ]

    precondition {
      condition     = var.outbound_type != "userAssignedNATGateway" || var.nat_gateway_attached
      error_message = "outbound_type userAssignedNATGateway requires a NAT Gateway associated with the node subnet."
    }
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  vm_size               = each.value.vm_size
  vnet_subnet_id        = var.node_subnet_id
  orchestrator_version  = var.kubernetes_version
  auto_scaling_enabled  = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  max_pods              = each.value.max_pods
  os_type               = "Linux"
  os_sku                = each.value.os_sku
  os_disk_type          = each.value.os_disk_type
  os_disk_size_gb       = each.value.os_disk_size_gb
  zones                 = each.value.zones
  node_labels           = merge({ "workload-class" = each.key }, each.value.node_labels)
  node_taints           = each.value.node_taints
  priority              = each.value.spot ? "Spot" : "Regular"
  spot_max_price        = each.value.spot ? -1 : null
  eviction_policy       = each.value.spot ? "Delete" : null

  host_encryption_enabled     = var.host_encryption_enabled
  temporary_name_for_rotation = "${substr(each.key, 0, 8)}tmp"
  tags                        = var.tags

  upgrade_settings {
    max_surge                     = each.value.max_surge
    drain_timeout_in_minutes      = 30
    node_soak_duration_in_minutes = 0
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# --- Container Insights: cost-optimised collection ------------------------------
# Only ContainerLogV2 + inventory + events, 5-minute interval, system namespaces
# excluded from log collection. Perf counters come from managed Prometheus instead.
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = "dcr-ci-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"
  description         = "Container Insights (cost-optimised) for ${var.name}"
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = var.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = var.container_insights_streams
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = var.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "5m"
          namespaceFilteringMode = "Exclude"
          namespaces             = ["kube-system", "gatekeeper-system", "azure-arc"]
          enableContainerLogV2   = true
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
  description             = "Container Insights DCR association"
}

# --- Managed Prometheus -----------------------------------------------------------
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  count = var.prometheus_enabled ? 1 : 0

  name                = "dce-prom-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  count = var.prometheus_enabled ? 1 : 0

  name                        = "dcr-prom-${var.name}"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  kind                        = "Linux"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus[0].id
  tags                        = var.tags

  destinations {
    monitor_account {
      monitor_account_id = var.monitor_workspace_id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  count = var.prometheus_enabled ? 1 : 0

  name                    = "dcra-prom-${var.name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus[0].id
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus_endpoint" {
  count = var.prometheus_enabled ? 1 : 0

  # The name "configurationAccessEndpoint" is mandatory for DCE associations.
  name                        = "configurationAccessEndpoint"
  target_resource_id          = azurerm_kubernetes_cluster.this.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus[0].id
}

# --- Control-plane logs: audit (admin actions only) and Entra auth (guard) ------
resource "azurerm_monitor_diagnostic_setting" "this" {
  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(var.control_plane_log_categories)

    content {
      category = enabled_log.value
    }
  }
}

# --- Deployment safeguards (Azure Policy-backed best-practice checks) -----------
resource "azurerm_kubernetes_cluster_deployment_safeguard" "this" {
  count = var.deployment_safeguards_level == null ? 0 : 1

  kubernetes_cluster_id        = azurerm_kubernetes_cluster.this.id
  level                        = var.deployment_safeguards_level
  pod_security_standards_level = "Baseline"
  excluded_namespaces          = ["kube-system", "gatekeeper-system"]
}
