# role-assignment

Creates Azure role assignments from a map with **static keys** (e.g.
`"kubelet-acr-pull"`), so `for_each` is plannable even when principal IDs are
only known after apply. Granting `Owner` or `User Access Administrator` is
rejected by validation; those require an out-of-band, reviewed process.

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `assignments` | Map of stable key => role assignment definition. | `map(object({scope = string, role_definition_name = string...` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `ids` | Map of key => role assignment ID. |
