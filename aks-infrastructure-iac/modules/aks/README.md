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

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | AKS cluster name. | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group for the cluster resource. | `string` |  | yes |
| `node_resource_group_name` | Name of the AKS-managed node resource group (MC_ group). | `string` |  | yes |
| `dns_prefix` | DNS prefix for the private API server FQDN. | `string` |  | yes |
| `tenant_id` | Entra tenant ID. | `string` |  | yes |
| `kubernetes_version` | <<-EOT     Kubernetes minor version alias (e.g. "1.36"). AKS resolves the alias to the     latest supported patch, and automatic_upgrade_channel = "patch" keeps it there.     Check support with: az aks get-versions -l <region> -o table   EOT | `string` |  | yes |
| `sku_tier` | Free (no API server SLA, POC) or Standard (financially backed SLA, production). | `string` | `Free` | no |
| `private_dns_zone_id` | \"System\" (AKS-managed zone) or the ID of a custom privatelink.<region>.azmk8s.io zone. | `string` | `System` | no |
| `admin_group_object_ids` | Entra group object IDs granted cluster-admin (platform administrators). | `list(string)` |  | yes |
| `control_plane_identity_id` | User-assigned identity ID for the AKS control plane (needs Network Contributor on the node subnet and Managed Identity Operator on the kubelet identity). | `string` |  | yes |
| `kubelet_identity` | Pre-created kubelet identity (AcrPull, Azure Files mount). | `object({id = string, client_id = string, principal_id = s...` |  | yes |
| `automatic_upgrade_channel` | patch (recommended), stable, rapid, node-image or none. | `string` | `patch` | no |
| `maintenance_day` | Day of week for planned maintenance. | `string` | `Sunday` | no |
| `maintenance_start_time` | Maintenance start time (HH:MM, UTC). | `string` | `02:00` | no |
| `node_subnet_id` | Subnet for node NICs (CNI Overlay: pods do not consume VNet IPs). | `string` |  | yes |
| `pod_cidr` | Overlay pod CIDR. Must not overlap the VNet, peered networks or service CIDR. | `string` | `192.168.0.0/16` | no |
| `service_cidr` | Kubernetes service CIDR. The DNS service IP is the 10th address. | `string` | `172.16.0.0/16` | no |
| `outbound_type` | loadBalancer (POC default), userAssignedNATGateway, or userDefinedRouting (Azure Firewall, production). | `string` | `loadBalancer` | no |
| `nat_gateway_attached` | Set true when a NAT Gateway is associated with the node subnet. | `bool` | `false` | no |
| `system_node_pool` | System node pool settings (tainted CriticalAddonsOnly). | `object({vm_size = string, min_count = number, max_count =...` |  | yes |
| `user_node_pools` | Map of user node pools keyed by pool name (lowercase, <= 12 chars). | `map(object({vm_size = string, min_count = number, max_cou...` |  | yes |
| `host_encryption_enabled` | Encrypt temp disks, caches and OS/data flows at the VM host (no extra cost; requires the Microsoft.Compute/EncryptionAtHost subscription feature, see scripts/register-providers.sh). | `bool` | `true` | no |
| `agic_enabled` | Enable the Application Gateway Ingress Controller add-on (false = in-cluster ingress controller mode). | `bool` | `true` | no |
| `application_gateway_id` | Application Gateway ID targeted by AGIC (required when agic_enabled). | `string` | `null` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for Container Insights and control-plane logs. | `string` |  | yes |
| `container_insights_streams` | Container Insights streams to collect (cost profile). | `list(string)` | `["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory", "Microsoft-KubeNodeInventory"]` | no |
| `control_plane_log_categories` | AKS resource log categories. kube-audit-admin excludes read events and is much cheaper than kube-audit. | `list(string)` | `["kube-audit-admin", "guard"]` | no |
| `prometheus_enabled` | Send metrics to managed Prometheus (monitor_workspace_id). | `bool` | `true` | no |
| `alerts_enabled` | Create Prometheus alert rules routed to action_group_id. | `bool` | `true` | no |
| `monitor_workspace_id` | Azure Monitor workspace ID for managed Prometheus (null = disabled). | `string` | `null` | no |
| `action_group_id` | Action group for Prometheus alert rules. | `string` | `null` | no |
| `defender_enabled` | Microsoft Defender for Containers sensor (billed per vCore). | `bool` | `false` | no |
| `deployment_safeguards_level` | AKS Deployment Safeguards: null (off), Warn or Enforce. | `string` | `Warn` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | AKS cluster ID (scope for Azure RBAC Kubernetes role assignments). |
| `name` | AKS cluster name. |
| `oidc_issuer_url` | OIDC issuer used by workload identity federated credentials. |
| `private_fqdn` | Private API server FQDN. |
| `node_resource_group` | AKS-managed node resource group. |
| `node_resource_group_id` | Node resource group ID. |
| `current_kubernetes_version` | Resolved Kubernetes patch version. |
| `key_vault_secrets_provider_identity` | Identity created by the Key Vault CSI add-on (unused: workloads use workload identity). |
| `agic_identity_object_id` | Object ID of the AGIC add-on identity (null when AGIC is disabled). |
