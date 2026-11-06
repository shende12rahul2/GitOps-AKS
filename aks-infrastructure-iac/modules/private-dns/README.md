# private-dns

Creates private DNS zones and links each zone to every VNet in
`virtual_network_ids` (auto-registration disabled). Links are keyed
`<zone>|<vnet key>` for stable identity.

Zones used by this POC:

| Zone | Used by | Mechanism |
|---|---|---|
| `privatelink.vaultcore.azure.net` | Key Vault | Private endpoint |
| `privatelink.file.core.windows.net` | Azure Files | Private endpoint |
| `privatelink.redis.azure.net` | Azure Managed Redis | Private endpoint |
| `<prefix>.private.postgres.database.azure.com` | PostgreSQL Flexible Server | VNet integration (delegated subnet) |
| `privatelink.azurecr.io` | ACR Premium (optional) | Private endpoint |
| `poc.example.com` (configurable) | App/admin hostnames | A records to the ingress IP |

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `resource_group_name` | Resource group that owns the private DNS zones (normally the network resource group). | `string` |  | yes |
| `zone_names` | Private DNS zone names, e.g. privatelink.vaultcore.azure.net. | `list(string)` |  | yes |
| `virtual_network_ids` | Map of short key => VNet ID to link every zone to. | `map(string)` |  | yes |
| `tags` | Resource tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `zone_ids` | Map of zone name => zone ID. |
| `zone_names` | Zone names. |
