locals {
  waf_enabled = var.sku == "WAF_v2"

  frontend_private = "fip-private"
  frontend_public  = "fip-public"

  # Bootstrap-only objects. AGIC replaces listeners, rules, pools, probes,
  # settings and certificates as soon as it reconciles Ingress resources.
  bootstrap_pool     = "pool-bootstrap"
  bootstrap_settings = "settings-bootstrap"
  bootstrap_listener = "listener-bootstrap"
  bootstrap_rule     = "rule-bootstrap"
}

resource "azurerm_public_ip" "this" {
  count = var.public_frontend_enabled ? 1 : 0

  name                = "pip-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

resource "azurerm_web_application_firewall_policy" "this" {
  count = local.waf_enabled ? 1 : 0

  name                = "waf-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode
    request_body_check          = true
    request_body_enforcement    = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = var.waf_default_rule_set_version
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = var.waf_bot_rule_set_version
    }
  }

  # Example custom rule: rate limit per client IP to blunt brute-force/scraping.
  custom_rules {
    name                 = "RateLimitPerClientIp"
    priority             = 10
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = var.waf_rate_limit_per_minute
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      negation_condition = true
      match_values       = ["255.255.255.255/32"]
    }
  }
}

resource "azurerm_application_gateway" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  zones               = var.zones
  http2_enabled       = true
  firewall_policy_id  = local.waf_enabled ? azurerm_web_application_firewall_policy.this[0].id : null

  force_firewall_policy_association = local.waf_enabled
  tags                              = var.tags

  sku {
    name = var.sku
    tier = var.sku
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  gateway_ip_configuration {
    name      = "gwip"
    subnet_id = var.subnet_id
  }

  # Private frontend is always present. Admin hostnames (Argo CD, Airflow) and the
  # default POC application listener bind here (annotation use-private-ip=true).
  frontend_ip_configuration {
    name                          = local.frontend_private
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip_address
  }

  dynamic "frontend_ip_configuration" {
    for_each = var.public_frontend_enabled ? [1] : []

    content {
      name                 = local.frontend_public
      public_ip_address_id = azurerm_public_ip.this[0].id
    }
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  # TLS 1.2+ with strong cipher suites only.
  ssl_policy {
    policy_type = "Predefined"
    policy_name = var.ssl_policy_name
  }

  backend_address_pool {
    name = local.bootstrap_pool
  }

  backend_http_settings {
    name                  = local.bootstrap_settings
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = local.bootstrap_listener
    frontend_ip_configuration_name = local.frontend_private
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.bootstrap_rule
    rule_type                  = "Basic"
    priority                   = 19500
    http_listener_name         = local.bootstrap_listener
    backend_address_pool_name  = local.bootstrap_pool
    backend_http_settings_name = local.bootstrap_settings
  }

  lifecycle {
    # AGIC is the owner of the routing configuration. Terraform owns the gateway
    # itself (SKU, scale, subnet, frontends, TLS policy, WAF policy association).
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      redirect_configuration,
      request_routing_rule,
      rewrite_rule_set,
      ssl_certificate,
      trusted_root_certificate,
      url_path_map,
      tags,
    ]

    precondition {
      condition     = can(cidrhost("${var.private_ip_address}/32", 0))
      error_message = "private_ip_address must be a valid IPv4 address inside the gateway subnet."
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.diagnostics_enabled ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_application_gateway.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  dynamic "enabled_log" {
    for_each = local.waf_enabled ? [1] : []

    content {
      category = "ApplicationGatewayFirewallLog"
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
