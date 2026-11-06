# AKS sizing

Sizing is computed from the **rendered** resource requests of the dev
environment (`aks-gitops-deployment/scripts/render.py dev`), not guessed.

## Workload requests (dev, rendered)

| Workload | Pods | CPU request | Memory request |
|---|---|---|---|
| Airflow (api-server, scheduler, dag-processor, triggerer, worker, statsd, kv-sync, git-sync sidecars) | 7 | 1.44 | 4.85 GiB |
| Argo CD (controller, server, repo-server, applicationset, redis) | 5 | 0.45 | 1.00 GiB |
| Five microservices (1 replica each) | 5 | 0.23 | 0.54 GiB |
| cert-manager (controller, webhook, cainjector) | 3 | 0.03 | 0.16 GiB |
| **Total user workloads** | **20** | **~2.15** | **~6.55 GiB** |

Prod (2 replicas, 2 API servers/schedulers/workers): apps 0.45 CPU / 1.1 GiB at
`minReplicas` (about 1.0 CPU / 2.5 GiB at HPA max), Airflow 2.5 CPU / 8.2 GiB.

## Node allocatable (per node)

AKS reserves CPU and memory for kubelet/OS, plus the eviction threshold. With
`max_pods = 110` (AKS >= 1.29 memory reservation is about 20 MiB x max pods + 50 MiB, plus
100 MiB eviction threshold); these are approximations, read the real values with
`kubectl describe node | grep -A6 Allocatable`.

| VM | vCPU / RAM | Allocatable (approx.) | DaemonSets (cilium, ama-logs, ama-metrics-node, CSI x3, KV provider) | Left for workloads |
|---|---|---|---|---|
| Standard_D2ads_v5 | 2 / 8 GiB | ~1.9 CPU / ~5.4 GiB | ~0.4 CPU / ~1.0 GiB | ~1.5 CPU / ~4.4 GiB |
| Standard_D4ads_v5 | 4 / 16 GiB | ~3.86 CPU / ~13.3 GiB | ~0.4 CPU / ~1.0 GiB | ~3.4 CPU / ~12.3 GiB |

## Choice

- **System pool: 1 x Standard_D2ads_v5** (autoscale 1-2), tainted
  `CriticalAddonsOnly`: CoreDNS, metrics-server, konnectivity, AGIC, Cilium
  operator, ama-metrics/ama-logs replicas, Gatekeeper (Azure Policy). AKS requires at least 2 vCPU / 4 GiB
  for system pools.
- **User pool `apps`: 2 x Standard_D4ads_v5** (autoscale 2-3): capacity
  ~6.8 CPU / ~24.6 GiB for ~2.15 CPU / ~6.6 GiB of requests = **~32 % CPU, ~27 %
  memory**. The headroom absorbs rolling-update surge (maxSurge 1 per
  Deployment), Celery task bursts, migration Jobs and a node drain during
  upgrades (one node must hold everything: 2.15 / 3.4 CPU, 6.6 / 12.3 GiB, fits).
- Two user nodes are also the minimum for the cross-node Azure Files test.
- `Standard_D*ads_v5` has a local temp disk, so OS disks are **ephemeral**
  (no managed OS disk cost, faster reimage): 64 GiB (D2ads, 75 GiB temp) and
  128 GiB (D4ads, 150 GiB temp).

Rejected alternatives:

| Option | Why not |
|---|---|
| 3 x D2ads_v5 user nodes | ~4.5 CPU usable but 1 GiB+ Airflow pods fragment badly; a drain leaves 2 nodes at ~75 % CPU requests |
| B-series (burstable) nodes | CPU credits run out under Airflow parsing/scheduling; unpredictable latency |
| No separate system pool | violates the requirement and lets workloads starve CoreDNS |
| Spot user pool | evictions interrupt Celery tasks; possible later for a dedicated Airflow worker pool |

Check region availability first: `az vm list-skus -l eastus2 --size Standard_D4ads_v5 -o table`
(v6 equivalents `Standard_D4ads_v6` are an alternative where available).

## Single-zone POC vs production HA

| Aspect | POC (dev/test) | Production |
|---|---|---|
| AKS tier | Free (no API SLA) | Standard (financially backed SLA) |
| Zones | none (regional) | system 3 x D4ads_v5 and apps 3-6 x D4ads_v5 across zones 1-3 |
| Workloads | 1 replica | 2+ replicas, HPA, PDBs, zone topology spread |
| App Gateway | autoscale 0-2, regional | min 2, zones 1-3 |
| PostgreSQL | Burstable B2s, no HA | GP D2ds_v5, zone-redundant HA, PgBouncer |
| Redis | Balanced_B0, no HA | Balanced_B5 (or dedicated broker), HA |
| Storage | LRS | ZRS |
| Failure impact | a node/zone failure causes downtime until rescheduling; no SLA | survives a zone loss |
