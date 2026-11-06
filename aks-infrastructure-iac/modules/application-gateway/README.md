# application-gateway

Application Gateway v2 (`WAF_v2` or `Standard_v2`) for the AGIC add-on.

- **Private frontend always** (static IP in the gateway subnet). The public
  frontend is optional (`public_frontend_enabled`). A private-only gateway needs
  the `EnableApplicationGatewayNetworkIsolation` subscription feature and the
  subnet delegated to `Microsoft.Network/applicationGateways`.
- **WAF policy**: Microsoft Default Rule Set 2.1 + Bot Manager 1.1, request body
  inspection, per-client-IP rate limiting custom rule, Detection/Prevention mode.
- **TLS policy** `AppGwSslPolicy20220101S` (TLS 1.2+, strong ciphers), HTTP/2.
- **Ownership split**: Terraform owns the gateway (SKU, scale, subnet, frontends,
  TLS policy, WAF association). AGIC owns listeners, rules, pools, probes,
  settings and certificates; those are in `ignore_changes`.
- Access and firewall logs to Log Analytics (resource-specific tables).

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Application Gateway name. | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `sku` | WAF_v2 (recommended, OWASP/DRS protection) or Standard_v2 (lower fixed cost, no WAF). | `string` | `WAF_v2` | no |
| `subnet_id` | Dedicated gateway subnet (/24 or smaller is required by AGIC with CNI Overlay). | `string` |  | yes |
| `private_ip_address` | Static private frontend IP inside the gateway subnet. | `string` |  | yes |
| `public_frontend_enabled` | <<-EOT     false (default) = private-only gateway (requires the EnableApplicationGatewayNetworkIsolation     subscription feature and subnet delegation to Microsoft.Network/applicationGateways).     true = also create a public frontend for internet-facing WAF-protected applications.   EOT | `bool` | `false` | no |
| `zones` | Availability zones (null = regional, cheapest; [\"1\",\"2\",\"3\"] for production). | `list(string)` | `null` | no |
| `min_capacity` | Autoscale minimum capacity units (0 = no reserved capacity). | `number` | `0` | no |
| `max_capacity` | Autoscale maximum capacity units. | `number` | `2` | no |
| `ssl_policy_name` | Predefined TLS policy (AppGwSslPolicy20220101S = TLS 1.2+ with strong ciphers). | `string` | `AppGwSslPolicy20220101S` | no |
| `waf_mode` | Detection (log only, tune rules first) or Prevention (block). | `string` | `Prevention` | no |
| `waf_default_rule_set_version` | Microsoft_DefaultRuleSet version. | `string` | `2.1` | no |
| `waf_bot_rule_set_version` | Microsoft_BotManagerRuleSet version. | `string` | `1.1` | no |
| `waf_rate_limit_per_minute` | Requests per minute per client IP before the WAF blocks. | `number` | `600` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for access and WAF logs. | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Application Gateway ID (AGIC target). |
| `name` | Application Gateway name. |
| `private_ip_address` | Private frontend IP (target of private DNS A records). |
| `public_ip_address` | Public frontend IP (null when private-only). |
| `waf_policy_id` | WAF policy ID (null for Standard_v2). |
