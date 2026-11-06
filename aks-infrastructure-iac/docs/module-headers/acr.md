# acr

Azure Container Registry with Entra-only access: admin user and anonymous pull
disabled. AKS pulls with the kubelet identity (`AcrPull`), CI pushes with a
GitHub OIDC identity (`AcrPush`).

| SKU | Private endpoint | Firewall | Retention policy | Typical use |
|---|---|---|---|---|
| Basic | no | no | no | lab |
| Standard | no | no | no | **POC default** |
| Premium | yes | yes | yes | production |

A `precondition` blocks `private_endpoint_enabled = true` on non-Premium SKUs.
