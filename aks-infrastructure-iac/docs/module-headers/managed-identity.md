# managed-identity

User-assigned managed identity with federated identity credentials (max 20).

- AKS workload identity: `issuer = <AKS OIDC issuer>`,
  `subject = system:serviceaccount:<namespace>:<service account>`.
- GitHub Actions: `issuer = https://token.actions.githubusercontent.com`,
  `subject = repo:<org>/<repo>:environment:<env>` (or `:ref:refs/heads/main`).

No client secrets or certificates are created anywhere in this design.
