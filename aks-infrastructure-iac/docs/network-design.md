# Network design

## Address plan (per environment)

Each environment gets its own `/16` so environments can later be peered to a hub
without overlap: dev `10.10.0.0/16`, test `10.20.0.0/16`, prod `10.30.0.0/16`.
Subnets are derived with `cidrsubnet()` from that single input.

| Subnet | dev CIDR | Size | Purpose / constraints |
|---|---|---|---|
| `snet-aks-nodes` | 10.10.0.0/22 | 1,019 IPs | Node NICs only (CNI Overlay). Room for 3x surge upgrades and a future pool. Internal LB IP 10.10.3.232 is reserved for the `internal` ingress mode. |
| `snet-appgw` | 10.10.4.0/24 | 251 IPs | Dedicated to Application Gateway v2. AGIC with CNI Overlay requires **/24 or smaller**. Delegated to `Microsoft.Network/applicationGateways` for private-only gateways. |
| `snet-private-endpoints` | 10.10.5.0/24 | 251 IPs | Key Vault, Azure Files, Managed Redis (+ ACR in prod). PE network policies **enabled** so the NSG applies. |
| `snet-postgresql` | 10.10.6.0/27 | 27 IPs | Delegated to `Microsoft.DBforPostgreSQL/flexibleServers` (VNet integration). |
| `snet-mgmt` | 10.10.7.0/27 | 27 IPs | Optional jumpbox. |
| `AzureBastionSubnet` | 10.10.7.64/26 | 59 IPs | Only for Bastion Standard (prod). |
| Pod CIDR (overlay) | 192.168.0.0/16 | | Never routed in the VNet. |
| Service CIDR | 172.16.0.0/16 | | DNS service IP 172.16.0.10. |

## Azure CNI Overlay assessment

| Option | Pod IPs | VNet IPs per node | AGIC | NetworkPolicy | Verdict |
|---|---|---|---|---|---|
| kubenet | overlay | 1 | yes (route table) | Calico only | Retiring; no |
| Azure CNI (flat) | VNet | 1 + max pods | yes | yes | Burns VNet space (110 IPs/node) |
| **Azure CNI Overlay + Cilium** | overlay | 1 | **yes (AGIC >= 1.9.1, subnet <= /24)** | **Cilium (eBPF)** | **Chosen** |

Overlay keeps the VNet small, scales to large clusters, and Cilium enforces
standard Kubernetes `NetworkPolicy` without a separate policy engine. Pods reach
VNet resources SNAT'ed to the node IP, which is why NSGs reference the node subnet.
Advanced Container Networking Services (FQDN policies, flow logs) is an optional
paid add-on for production.

## Private connectivity per service

The services deliberately use different supported mechanisms:

| Service | Mechanism | DNS | Port | Public access |
|---|---|---|---|---|
| AKS API server | Private cluster (AKS-managed private endpoint) | `privatelink.<region>.azmk8s.io` (System) | 443 | none; `az aks command invoke` via ARM |
| PostgreSQL Flexible | **VNet integration** (delegated subnet) | `<prefix>.private.postgres.database.azure.com` | 5432 (6432 PgBouncer) | disabled |
| Managed Redis | **Private endpoint** (`redisEnterprise`) | `privatelink.redis.azure.net` | 10000 TLS | `public_network_access = Disabled` |
| Azure Files | **Private endpoint** (`file`) | `privatelink.file.core.windows.net` | 445 SMB | `public_network_access = Disabled` |
| Key Vault | **Private endpoint** (`vault`) | `privatelink.vaultcore.azure.net` | 443 | disabled (ARM control plane still works) |
| ACR | Public endpoint, Entra-only (POC); **private endpoint** with Premium (prod) | `privatelink.azurecr.io` | 443 | GitHub-hosted runners need it in the POC |
| App Gateway | Private frontend IP (+ optional public WAF frontend) | `poc.example.com` A records | 80/443 | optional |

PostgreSQL uses VNet integration because it needs no private endpoint (no extra
cost) and keeps the server off the public network entirely. A server created
with VNet integration cannot be converted to the private-endpoint model later;
choose private endpoints instead for hub-and-spoke with central DNS.

## Network security groups

| NSG | Inbound allowed | Notes |
|---|---|---|
| aks-nodes | App Gateway subnet -> any (AGIC to pod IPs); Azure defaults | AKS adds its own NIC-level rules. No deny rules here (would break node bootstrap). |
| appgw | GatewayManager 65200-65535, AzureLoadBalancer, VNet -> 80/443, optional Internet -> 80/443 | Explicit deny of other VNet traffic (priority 4000). |
| private-endpoints | node + mgmt subnets -> 443, 445, 10000 | Deny other VNet traffic. |
| postgresql | node + mgmt subnets -> 5432, 6432 | Deny other VNet traffic. |
| mgmt | Bastion (168.63.129.16 for Developer SKU, Bastion subnet for Standard) -> 22 | Deny other VNet traffic. |

## Kubernetes NetworkPolicies

`kubernetes/network-policies` + per-chart policies (Cilium enforces them):

- `apps`: default deny (ingress + egress). Egress: DNS, other app pods :8000,
  PostgreSQL subnet :5432, private endpoints :10000/:443, Internet :443 (Entra ID).
  Ingress per service: only its declared callers, Airflow workers, the ingress
  source (App Gateway subnet or `ingress` namespace) and `kube-system` (metrics).
- `airflow`: default deny; intra-namespace traffic; egress to PostgreSQL, Redis,
  `apps` :8000, Internet :443 (Entra sign-in) and :22 (GitHub SSH for Git-Sync).
  UI ingress only from the ingress source to `api-server:8080`.
- `platform-jobs`: DNS, PostgreSQL, Internet :443.

NetworkPolicies cannot match FQDNs. Internet egress on 443 is therefore broad in
the POC; production should force egress through Azure Firewall (UDR,
`outbound_type = userDefinedRouting`) with an FQDN allow list
(`login.microsoftonline.com`, `*.azurecr.io`, `mcr.microsoft.com`,
`github.com`, AKS required endpoints) or use ACNS FQDN filtering.

## Egress options evaluated

| Option | Monthly cost driver | Deterministic IP | FQDN filtering | POC choice |
|---|---|---|---|---|
| Standard Load Balancer outbound | 1 public IP (+ rules) | yes (LB IP) | no | **dev/test** |
| NAT Gateway | hourly + per-GB | yes | no | **prod** (`nat_gateway_enabled`) |
| Azure Firewall Basic/Standard | hourly + per-GB (largest) | yes | yes | production with compliance needs |

Private-only Application Gateways cannot egress to the Internet, which is fine
here: TLS certificates come from Kubernetes secrets, not Key Vault URLs.

## Required outbound endpoints (for a future firewall)

AKS: `mcr.microsoft.com`, `*.data.mcr.microsoft.com`, `management.azure.com`,
`login.microsoftonline.com`, `packages.microsoft.com`, `acs-mirror.azureedge.net`,
`<region>.dp.kubernetesconfiguration.azure.com`, monitoring (`*.ods.opinsights.azure.com`,
`*.oms.opinsights.azure.com`, `*.monitoring.azure.com`, `*.ingest.monitor.azure.com`).
Workloads: `<acr>.azurecr.io`, `<acr>.<region>.data.azurecr.io` (Premium),
`github.com:22` (Git-Sync), `airflow.apache.org` / chart repos (Argo CD) or an
ACR chart mirror.
