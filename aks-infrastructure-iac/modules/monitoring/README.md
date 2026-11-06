# monitoring

Log Analytics workspace (local auth disabled, 30-day retention, daily cap),
Azure Monitor workspace (managed Prometheus) and the critical-alert action group.
Per-resource diagnostic settings and alerts live in the resource modules.

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group for monitoring resources. | `string` |  | yes |
| `log_analytics_name` | Log Analytics workspace name. | `string` |  | yes |
| `monitor_workspace_name` | Azure Monitor workspace (managed Prometheus) name. | `string` |  | yes |
| `action_group_name` | Action group name for critical alerts. | `string` |  | yes |
| `retention_in_days` | Interactive retention. 30 days is included in PerGB2018 pricing; longer retention is billed. | `number` | `30` | no |
| `daily_quota_gb` | Daily ingestion cap in GB (-1 = unlimited). A cap protects a POC budget but drops data once reached. | `number` | `2` | no |
| `prometheus_enabled` | Create an Azure Monitor workspace for managed Prometheus. | `bool` | `true` | no |
| `alert_email_addresses` | Map of receiver key => email address for the critical alert action group. | `map(string)` | `{}` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `log_analytics_workspace_id` | Log Analytics workspace resource ID. |
| `log_analytics_workspace_name` | Log Analytics workspace name. |
| `monitor_workspace_id` | Azure Monitor workspace ID (null when Prometheus is disabled). |
| `action_group_id` | Critical alert action group ID. |
