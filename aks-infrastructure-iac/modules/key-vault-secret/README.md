# key-vault-secret

Writes one Key Vault secret through the **ARM control plane**
(`Microsoft.KeyVault/vaults/secrets` in an ARM template deployment) and grants
`Key Vault Secrets User` on **that secret only** to the listed principals.

Why ARM: the vault has no public endpoint, and GitHub-hosted runners cannot
reach its private endpoint. ARM can create secrets regardless of the vault
firewall for a caller with `Microsoft.KeyVault/vaults/secrets/write`. The value
is a `securestring` parameter (not kept in deployment history); it is stored in
Terraform state, which is protected accordingly.

- `operator_managed = false`: Terraform owns the value (generated passwords,
  connection strings).
- `operator_managed = true`: Terraform creates a placeholder once and ignores
  later changes. Operators set the real value with `scripts/set-operator-secret.sh`
  (SSH deploy keys, OAuth client secrets).

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `key_vault_name` | Target Key Vault name. | `string` |  | yes |
| `key_vault_resource_group_name` | Resource group containing the Key Vault (the ARM deployment runs there). | `string` |  | yes |
| `secret_name` | Secret name (1-127 alphanumerics and hyphens). | `string` |  | yes |
| `value` | Secret value. For operator-managed secrets this is only the initial placeholder. | `string` |  | yes |
| `content_type` | Content type hint, e.g. text/plain, application/x-ssh-key, application/x-connection-string. | `string` | `text/plain` | no |
| `operator_managed` | true = Terraform creates a placeholder once and never overwrites the value. | `bool` | `false` | no |
| `reader_principal_ids` | Map of stable key => principal ID granted Key Vault Secrets User on this secret only. | `map(string)` | `{}` | no |
| `tags` | Secret tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | ARM resource ID of the secret (RBAC scope). |
| `versionless_uri` | Versionless secret URI (https://<vault>.vault.azure.net/secrets/<name>). |
| `name` | Secret name. |
