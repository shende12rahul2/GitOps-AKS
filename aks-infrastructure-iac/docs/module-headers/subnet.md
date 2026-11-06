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
