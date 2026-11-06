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
