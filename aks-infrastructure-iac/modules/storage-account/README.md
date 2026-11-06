# storage-account

Hardened storage account for Azure Files:

- Public network access **disabled**; private endpoints per subresource.
- **Shared key access disabled** and **SMB OAuth enabled**: the Azure Files CSI
  driver mounts SMB shares with the kubelet managed identity
  (`mountWithManagedIdentity`), so no account key exists in Kubernetes or Git.
- SMB 3.1.1 only, AES-GCM channel encryption, TLS 1.2, infrastructure encryption.
- Share soft delete (default 7 days).
- File service metrics and write/delete logs to Log Analytics.

Use `account_kind = "FileStorage"` + `account_tier = "Premium"` for NFS or
latency-sensitive workloads (provisioned billing).

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Storage account name (3-24 lowercase alphanumerics, globally unique). | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `account_kind` | StorageV2 (Standard SMB shares) or FileStorage (Premium SMB/NFS shares). | `string` | `StorageV2` | no |
| `account_tier` | Standard (pay-as-you-go HDD) or Premium (provisioned SSD, required for NFS). | `string` | `Standard` | no |
| `replication_type` | LRS (POC), ZRS (production), GRS/GZRS (Standard only, DR). | `string` | `LRS` | no |
| `https_traffic_only_enabled` | Require encryption in transit (must be false for NFS shares without EiT). | `bool` | `true` | no |
| `shared_access_key_enabled` | Allow account-key/SAS auth. false = Entra only (requires managed-identity SMB mounts). | `bool` | `false` | no |
| `smb_oauth_enabled` | Enable SMB OAuth so managed identities can mount SMB shares without keys. | `bool` | `true` | no |
| `share_soft_delete_days` | Soft delete retention for file shares. | `number` | `7` | no |
| `private_endpoints` | Map of storage subresource (file, blob, ...) => private DNS zone ID. | `map(string)` | `{}` | no |
| `private_endpoint_subnet_id` | Private endpoint subnet. | `string` |  | yes |
| `file_log_categories` | File service log categories (StorageRead, StorageWrite, StorageDelete). | `list(string)` | `["StorageWrite", "StorageDelete"]` | no |
| `log_analytics_workspace_id` | Log Analytics workspace. | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Storage account ID. |
| `name` | Storage account name. |
| `primary_file_host` | File endpoint host (<name>.file.core.windows.net, resolves privately). |
