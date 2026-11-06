# aks

Private AKS cluster following the AKS baseline:

- **Private API server** (`private_cluster_enabled`, no public FQDN) with
  `run_command_enabled` as the break-glass path (`az aks command invoke`).
- **Entra ID + Azure RBAC for Kubernetes**, local accounts disabled.
- **Azure CNI Overlay powered by Cilium** (pods use a non-routable overlay CIDR;
  Cilium enforces `NetworkPolicy`).
- **Workload Identity + OIDC issuer**, **Key Vault CSI driver** (2-minute rotation),
  **Azure Files/Disk CSI**, snapshot controller.
- Separate **system pool** (tainted `CriticalAddonsOnly`) and **user pools**
  (`for_each`), ephemeral OS disks, autoscaler with `least-waste`.
- `patch` auto-upgrade channel + `NodeImage` OS channel inside weekly maintenance windows.
- Optional **AGIC add-on** (`agic_enabled`).
- **Container Insights** with a cost-optimised DCR (ContainerLogV2, events and
  inventory only; system namespaces excluded; 5-minute interval) and
  **managed Prometheus** (DCE/DCR/DCRA) with critical alert rules.
- Control-plane logs: `kube-audit-admin` (writes only) and `guard` (Entra auth).
- **Deployment Safeguards** (`Warn` in dev, `Enforce` in prod).

Pre-requisite role assignments (created by the platform root, before the cluster):
control-plane identity → *Network Contributor* on the node subnet and
*Managed Identity Operator* on the kubelet identity.

```hcl
module "aks" {
  source                    = "../../../modules/aks"
  name                      = "aks-akspoc-dev-eus2"
  kubernetes_version        = "1.36"
  admin_group_object_ids    = [var.entra_group_object_ids.platform_admins]
  control_plane_identity_id = module.id_aks_control_plane.id
  kubelet_identity          = { id = ..., client_id = ..., principal_id = ... }
  node_subnet_id            = local.foundation.subnet_ids["snet-aks-nodes"]
  system_node_pool          = { vm_size = "Standard_D2ads_v5", min_count = 1, max_count = 2 }
  user_node_pools           = { apps = { vm_size = "Standard_D4ads_v5", min_count = 2, max_count = 3 } }
  agic_enabled              = true
  application_gateway_id    = module.app_gateway[0].id
  # ...
}
```
