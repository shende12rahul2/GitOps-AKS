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
