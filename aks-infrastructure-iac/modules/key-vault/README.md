# key-vault

Key Vault with RBAC authorization, purge protection, public network access
disabled (unless `allowed_ip_ranges` is set), a private endpoint and audit logs.

Workloads read secrets through the Key Vault CSI driver using **workload
identity**, with RBAC scoped to individual secrets (`key-vault-secret` module).

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Key Vault name (3-24 chars, globally unique). | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `tenant_id` | Entra tenant ID. | `string` |  | yes |
| `purge_protection_enabled` | Enable purge protection (recommended; irreversible). | `bool` | `true` | no |
| `soft_delete_retention_days` | Soft delete retention (7-90 days). | `number` | `7` | no |
| `public_network_access_enabled` | Enable the public endpoint (firewall default-deny, only allowed_ip_ranges). false (default) = private endpoint and ARM control plane only. | `bool` | `false` | no |
| `allowed_ip_ranges` | Public IPs/CIDRs allowed through the firewall when public_network_access_enabled = true. | `list(string)` | `[]` | no |
| `private_endpoint_subnet_id` | Subnet for the Key Vault private endpoint. | `string` |  | yes |
| `private_dns_zone_id` | ID of privatelink.vaultcore.azure.net. | `string` |  | yes |
| `log_analytics_workspace_id` | Log Analytics workspace for audit logs. | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Key Vault ID. |
| `name` | Key Vault name. |
| `vault_uri` | Key Vault URI. |
