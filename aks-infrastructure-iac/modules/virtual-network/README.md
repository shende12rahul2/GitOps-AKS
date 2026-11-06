# virtual-network

Creates a VNet. Subnets are deliberately **not** declared inline; use the
`subnet` module so subnet changes never force VNet updates or perpetual diffs.

```hcl
module "vnet" {
  source              = "../../../modules/virtual-network"
  name                = "vnet-akspoc-dev-eus2"
  location            = "eastus2"
  resource_group_name = module.rg_network.name
  address_space       = ["10.10.0.0/16"]
}
```

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Virtual network name. | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group for the VNet. | `string` |  | yes |
| `address_space` | VNet address space (CIDR list). Must not overlap other environments or on-premises ranges. | `list(string)` |  | yes |
| `dns_servers` | Custom DNS servers. Empty list = Azure-provided DNS (168.63.129.16), required for private DNS zones unless you run a resolver. | `list(string)` | `[]` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for VNet metrics (used when diagnostics_enabled = true). | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | VNet ID. |
| `name` | VNet name. |
| `address_space` | VNet address space. |
