# resource-group

Creates a resource group with standard tags and an optional management lock
(`CanNotDelete` for long-lived production groups).

```hcl
module "rg_network" {
  source     = "../../../modules/resource-group"
  name       = "rg-akspoc-dev-eus2-network"
  location   = "eastus2"
  lock_level = null # "CanNotDelete" in prod
  tags       = module.naming.tags
}
```

Removing a lock is a deliberate two-step change: set `lock_level = null`, apply, then make the destructive change.
