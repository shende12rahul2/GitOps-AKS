# network-security

Network security group with rules declared as a map keyed by rule name. Each
rule is a separate `azurerm_network_security_rule`, so adding or removing a rule
never recreates the others. Single-value and multi-value prefix/port arguments
are selected automatically.

```hcl
module "nsg" {
  source              = "../../../modules/network-security"
  name                = "nsg-akspoc-dev-eus2-postgresql"
  location            = "eastus2"
  resource_group_name = module.rg_network.name
  rules = {
    AllowClusterToPostgres = {
      priority                     = 100
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "Tcp"
      source_address_prefixes      = ["10.10.0.0/22"]
      destination_address_prefixes = ["10.10.6.0/27"]
      destination_port_ranges      = ["5432"]
    }
  }
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
| `name` | NSG name. | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `rules` | <<-EOT     Map of security rules keyed by rule name. Azure default rules (AllowVnetInBound,     AllowAzureLoadBalancerInBound, DenyAllInBound, ...) still apply below priority 4096.   EOT | `map(object({priority = number, direction = string, access...` | `{}` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for NSG event logs (used when diagnostics_enabled = true). | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | NSG ID. |
| `name` | NSG name. |
