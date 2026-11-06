# subnet

Creates one subnet with optional delegation and NSG / route table / NAT Gateway
associations. Implicit "default outbound access" is always disabled.

Associations are passed as objects (`{ id = ... }`) instead of bare IDs so the
module can decide `count` at plan time even when the NSG is created in the same apply.

```hcl
module "subnet" {
  source               = "../../../modules/subnet"
  name                 = "snet-postgresql"
  resource_group_name  = module.rg_network.name
  virtual_network_name = module.vnet.name
  address_prefixes     = ["10.10.6.0/27"]
  delegation = {
    name         = "postgresql"
    service_name = "Microsoft.DBforPostgreSQL/flexibleServers"
    actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
  }
  network_security_group = { id = module.nsg["postgresql"].id }
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
| `name` | Subnet name. | `string` |  | yes |
| `resource_group_name` | Resource group of the parent VNet. | `string` |  | yes |
| `virtual_network_name` | Parent VNet name. | `string` |  | yes |
| `address_prefixes` | Subnet CIDR prefixes. | `list(string)` |  | yes |
| `private_endpoint_network_policies` | Enabled, Disabled, NetworkSecurityGroupEnabled or RouteTableEnabled. Use Enabled on private endpoint subnets so NSGs apply to PE traffic. | `string` | `Enabled` | no |
| `delegation` | Optional service delegation (e.g. Microsoft.DBforPostgreSQL/flexibleServers or Microsoft.Network/applicationGateways). | `object({name = string, service_name = string, actions = o...` | `null` | no |
| `network_security_group` | Optional NSG to associate: { id = <nsg id> }. | `object({id = string})` | `null` | no |
| `route_table` | Optional route table to associate (e.g. UDR to Azure Firewall in production): { id = <route table id> }. | `object({id = string})` | `null` | no |
| `nat_gateway` | Optional NAT Gateway for deterministic egress: { id = <nat gateway id> }. | `object({id = string})` | `null` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Subnet ID. |
| `name` | Subnet name. |
| `address_prefixes` | Subnet prefixes. |
