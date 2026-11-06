variable "name" {
  description = "Application Gateway name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "sku" {
  description = "WAF_v2 (recommended, OWASP/DRS protection) or Standard_v2 (lower fixed cost, no WAF)."
  type        = string
  default     = "WAF_v2"

  validation {
    condition     = contains(["WAF_v2", "Standard_v2"], var.sku)
    error_message = "sku must be WAF_v2 or Standard_v2."
  }
}

variable "subnet_id" {
  description = "Dedicated gateway subnet (/24 or smaller is required by AGIC with CNI Overlay)."
  type        = string
}

variable "private_ip_address" {
  description = "Static private frontend IP inside the gateway subnet."
  type        = string
}

variable "public_frontend_enabled" {
  description = <<-EOT
    false (default) = private-only gateway (requires the EnableApplicationGatewayNetworkIsolation
    subscription feature and subnet delegation to Microsoft.Network/applicationGateways).
    true = also create a public frontend for internet-facing WAF-protected applications.
  EOT
  type        = bool
  default     = false
}

variable "zones" {
  description = "Availability zones (null = regional, cheapest; [\"1\",\"2\",\"3\"] for production)."
  type        = list(string)
  default     = null
}

variable "min_capacity" {
  description = "Autoscale minimum capacity units (0 = no reserved capacity)."
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Autoscale maximum capacity units."
  type        = number
  default     = 2

  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 125
    error_message = "max_capacity must be between 1 and 125."
  }
}

variable "ssl_policy_name" {
  description = "Predefined TLS policy (AppGwSslPolicy20220101S = TLS 1.2+ with strong ciphers)."
  type        = string
  default     = "AppGwSslPolicy20220101S"
}

variable "waf_mode" {
  description = "Detection (log only, tune rules first) or Prevention (block)."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "waf_default_rule_set_version" {
  description = "Microsoft_DefaultRuleSet version."
  type        = string
  default     = "2.1"
}

variable "waf_bot_rule_set_version" {
  description = "Microsoft_BotManagerRuleSet version."
  type        = string
  default     = "1.1"
}

variable "waf_rate_limit_per_minute" {
  description = "Requests per minute per client IP before the WAF blocks."
  type        = number
  default     = 600
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for access and WAF logs."
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics_enabled" {
  description = "Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply."
  type        = bool
  default     = false
}
