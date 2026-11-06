# azure-files

Creates Azure file shares (quota, protocol, access tier) on an existing storage
account, plus capacity alerts at a percentage of quota.

**Terraform owns the shares.** Kubernetes consumes them only through statically
provisioned PersistentVolumes managed by Argo CD
(`aks-gitops-deployment/kubernetes/storage`). Dynamic provisioning is never used
for these shares, so the same share is never created by two owners.

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `storage_account_id` | Storage account ID hosting the shares. | `string` |  | yes |
| `resource_group_name` | Resource group for alert rules. | `string` |  | yes |
| `shares` | Map of share name => settings. | `map(object({quota_gb = number, protocol = optional(string...` |  | yes |
| `capacity_alert_percent` | Quota usage percentage that triggers an alert. | `number` | `80` | no |
| `action_group_id` | Action group for alerts (used when alerts_enabled = true). | `string` | `null` | no |
| `alerts_enabled` | Create metric alerts routed to action_group_id (explicit flag keeps count known at plan time). | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `share_names` | Share names. |
| `share_ids` | Map of share name => resource ID. |
| `share_urls` | Map of share name => URL. |
