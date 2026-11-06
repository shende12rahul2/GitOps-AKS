# jumpbox

Optional administration entry point for the private cluster: Ubuntu 24.04 VM
without a public IP, Entra ID SSH login (`AADSSHLoginForLinux`), trusted launch,
platform patching, nightly auto-shutdown, and Azure Bastion.

| Bastion SKU | Cost | Access |
|---|---|---|
| `Developer` | free | Portal SSH only (CLI administration from the VM) |
| `Standard` | billed hourly | Native client and `az network bastion tunnel` (open the Argo CD/Airflow UIs from a local browser) |

Cloud-init installs the Azure CLI, kubectl, kubelogin, Helm and the Argo CD CLI.

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Jumpbox VM name. | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `subnet_id` | Management subnet for the VM NIC. | `string` |  | yes |
| `virtual_network_id` | VNet ID (Bastion Developer SKU attaches to the VNet). | `string` |  | yes |
| `vm_size` | VM size. B-series is adequate for CLI administration. | `string` | `Standard_B2s` | no |
| `encryption_at_host_enabled` | Encryption at host (requires the subscription feature). | `bool` | `false` | no |
| `bootstrap_ssh_public_key` | Throw-away SSH public key required by the VM API (logins use Entra ID). | `string` |  | yes |
| `admin_group_object_ids` | Map of key => Entra group object ID allowed to log in as VM administrators. | `map(string)` |  | yes |
| `auto_shutdown_time` | Daily shutdown time (HHMM, UTC). | `string` | `1900` | no |
| `bastion_sku` | null (no Bastion), Developer (free, portal SSH only) or Standard (tunnelling for UI access). | `string` | `Developer` | no |
| `bastion_subnet_id` | AzureBastionSubnet ID (Standard SKU only). | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `vm_id` | Jumpbox VM ID. |
| `private_ip_address` | Jumpbox private IP. |
| `bastion_name` | Bastion host name (null when disabled). |
