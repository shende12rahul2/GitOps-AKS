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
