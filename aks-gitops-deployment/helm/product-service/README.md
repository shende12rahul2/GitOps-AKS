# product-service Helm chart

Products REST API with PostgreSQL (products_db) and Azure Managed Redis caching. Deployed by Argo CD (ApplicationSet `microservices`) into the
`apps` namespace. Values precedence:

1. `values.yaml` (this chart, defaults)
2. `environments/<env>/infrastructure.yaml` (`global`: tenant, Key Vault, identities, endpoints; generated from Terraform outputs)
3. `environments/<env>/apps/product-service.yaml` (image digest, replicas, resources, overrides)

| Feature | Values | Notes |
|---|---|---|
| Immutable image | `image.repository`, `image.digest` | Rendering fails without a `sha256:` digest |
| Workload identity | `workloadIdentity.*`, `serviceAccount.*` | SA `product-service` is the federated credential subject |
| PostgreSQL | `database.*` | Entra token auth as role `global.workloadIdentities.product-service.name` |
| Migrations | `migrations.enabled` | Argo CD Sync hook (wave 0) before the Deployment (wave 1) |
| Redis | `redis.*` | Entra auth, TLS :10000, keys prefixed `app:product-service` |
| Secrets | `keyVault.*` | Key Vault CSI files under `/mnt/secrets` (no Kubernetes Secret objects) |
| Shared Azure Files | `sharedStorage.*` | RWX PVC `shared-files-pvc` at `/mnt/shared` |
| Autoscaling | `autoscaling.*` | CPU (and optional memory) HPA; PDB when >1 replica |
| Placement | `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints` | Spread across nodes by default |
| Security | `podSecurityContext`, `securityContext` | Non-root 10001, read-only root FS, no capabilities (PSS restricted) |
| NetworkPolicy | `networkPolicy.*` | Allowed callers; namespace default-deny |

Validate locally:

```bash
helm lint . -f ci/test-values.yaml
helm template product-service . -f ci/test-values.yaml | kubeconform -strict -ignore-missing-schemas -
```
