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

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Resource group name (e.g. rg-akspoc-dev-eus2-network). | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `tags` | Tags applied to the resource group. | `map(string)` | `{}` | no |
| `lock_level` | Optional management lock: null (no lock), CanNotDelete or ReadOnly. | `string` | `null` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Resource group ID. |
| `name` | Resource group name. |
| `location` | Resource group location. |
