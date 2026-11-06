# managed-identity

User-assigned managed identity with federated identity credentials (max 20).

- AKS workload identity: `issuer = <AKS OIDC issuer>`,
  `subject = system:serviceaccount:<namespace>:<service account>`.
- GitHub Actions: `issuer = https://token.actions.githubusercontent.com`,
  `subject = repo:<org>/<repo>:environment:<env>` (or `:ref:refs/heads/main`).

No client secrets or certificates are created anywhere in this design.

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Identity name (id-<project>-<env>-<workload>). | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group for the identity. | `string` |  | yes |
| `federated_credentials` | <<-EOT     Map of credential name => { issuer, subject, audience }.     AKS workload identity: issuer = AKS OIDC issuer URL, subject = system:serviceaccount:<ns>:<sa>.     GitHub OIDC: issuer = https://token.actions.githubusercontent.com, subject = repo:<org>/<repo>:environment:<env>.   EOT | `map(object({issuer = string, subject = string, audience =...` | `{}` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Identity resource ID. |
| `name` | Identity name (also the PostgreSQL role name when used for Entra auth). |
| `client_id` | Client (application) ID used by azure-identity / workload identity annotations. |
| `principal_id` | Object (principal) ID used for role assignments. |
| `tenant_id` | Tenant ID. |
