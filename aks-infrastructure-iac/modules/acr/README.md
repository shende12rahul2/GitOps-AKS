# acr

Azure Container Registry with Entra-only access: admin user and anonymous pull
disabled. AKS pulls with the kubelet identity (`AcrPull`), CI pushes with a
GitHub OIDC identity (`AcrPush`).

| SKU | Private endpoint | Firewall | Retention policy | Typical use |
|---|---|---|---|---|
| Basic | no | no | no | lab |
| Standard | no | no | no | **POC default** |
| Premium | yes | yes | yes | production |

A `precondition` blocks `private_endpoint_enabled = true` on non-Premium SKUs.

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Registry name (5-50 alphanumerics, globally unique). | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `sku` | Basic, Standard or Premium. Premium is required for private endpoints, firewall rules, retention and geo-replication. | `string` | `Standard` | no |
| `public_network_access_enabled` | Premium only: allow the public endpoint (needed by GitHub-hosted runners unless self-hosted runners in the VNet are used). | `bool` | `true` | no |
| `private_endpoint_enabled` | Create a private endpoint (Premium only). | `bool` | `false` | no |
| `private_endpoint_subnet_id` | Private endpoint subnet ID (required when private_endpoint_enabled). | `string` | `null` | no |
| `private_dns_zone_id` | privatelink.azurecr.io zone ID (required when private_endpoint_enabled). | `string` | `null` | no |
| `untagged_retention_days` | Premium only: days before untagged manifests are purged. | `number` | `7` | no |
| `zone_redundancy_enabled` | Premium only: zone redundancy. | `bool` | `false` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for registry audit logs. | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Registry ID. |
| `name` | Registry name. |
| `login_server` | Registry login server (<name>.azurecr.io). |
