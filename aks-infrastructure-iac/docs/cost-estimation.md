# Cost estimation

> **Prices were not verifiable from the environment this POC was built in**
> (the Azure Retail Prices API was not reachable). The figures below are
> *indicative* list prices from the cited public sources (East US / East US 2,
> pay-as-you-go, USD, 730 h/month) and **must be confirmed** with
> `scripts/estimate-cost.py` (live Azure Retail Prices API) or the
> [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
> before any decision. Sources disagree in places; ranges are shown.

## Configurations compared

| Component | 1. Minimum viable secure POC | 2. Recommended dev (this repo's `dev`) | 3. Production-ready (`prod`) |
|---|---|---|---|
| AKS control plane | Free | Free | Standard (SLA) |
| System pool | 1 x D2ads_v5 | 1 x D2ads_v5 | 3 x D4ads_v5 (zonal) |
| User pool | 2 x D2ads_v5 | 2 x D4ads_v5 | 3-6 x D4ads_v5 (zonal) |
| Ingress | internal Traefik (`ingress_mode = internal`) | App Gateway WAF_v2, autoscale 0-2 | WAF_v2 min 2, zonal, public frontend |
| PostgreSQL | B_Standard_B1ms, 32 GiB | B_Standard_B2s, 32 GiB, 7-day PITR | GP_Standard_D2ds_v5, ZR HA, 128 GiB, 35 d, geo backup |
| Managed Redis | Balanced_B0, no HA | Balanced_B0, no HA | Balanced_B5, HA |
| Azure Files | Standard LRS 10 GiB | Standard LRS 2 x 10 GiB | Standard ZRS 150 GiB (+ backup) |
| Private endpoints | 3 (KV, Files, Redis) | 3 | 4 (+ ACR) |
| ACR | Basic | Standard | Premium + PE |
| Egress | LB outbound IP | LB outbound IP | NAT Gateway (or Azure Firewall) |
| Log Analytics | 30 d, 1 GB/day cap | 30 d, 2 GB/day cap | 90 d, no cap |
| Managed Prometheus | yes | yes | yes |
| Defender for Containers | off | off | on |
| Jumpbox / Bastion | `az aks command invoke` only | optional (Developer, free) | B2s + Bastion Standard |

## Major cost drivers (indicative)

| Driver | Indicative price | Source | Monthly (dev config) |
|---|---|---|---|
| Application Gateway WAF_v2 fixed fee | ~$0.443 / gateway-hour (Microsoft "snapshot for illustration", East US; one third-party guide lists $0.36) | [Microsoft: understanding pricing](https://learn.microsoft.com/azure/application-gateway/understanding-pricing), [wafpricing.com](https://wafpricing.com/azure-waf-pricing) | **~$320** + capacity units (~$0.0144/CU-hour) |
| D4ads_v5 Linux node | ~$0.206 / hour (East US; another aggregator shows $0.24) | [cloudprice.net](https://cloudprice.net/vm/Standard_D4ads_v5), [economize.cloud](https://www.economize.cloud/resources/azure/pricing/virtual-machine/linux-d4adsv5-standard/) | 2 nodes **~$300-350** |
| D2ads_v5 Linux node | roughly half of D4ads_v5 | (same family pricing) | 1 node **~$75-90** |
| PostgreSQL B2s compute | ~$25-50 / month (sources conflict) + storage/backup | [c3x.dev](https://c3x.dev/blog/azure-postgresql-flexible-server-cost/), [bytebase](https://www.bytebase.com/dbcost/azure-flexible-server-pricing/) | **~$30-60** |
| Managed Redis Balanced_B0 | ~$0.016-0.018 / hour (third-party; a Microsoft Q&A thread reports a 2026 price change) | [Microsoft Q&A](https://learn.microsoft.com/answers/questions/5764682/azure-managed-redis-pricing-doubled-from-2026) | **~$12-25** |
| Private endpoints, ACR Standard, Files, public IP, Log Analytics ingestion | small per-hour/per-GB meters | run the script | **~$40-90** |

Indicative totals (to be confirmed):

| Configuration | Indicative monthly | Notes |
|---|---|---|
| 1. Minimum viable secure POC | **~$280-400** | no App Gateway; Traefik internal LB |
| 2. Recommended dev | **~$800-950** | App Gateway WAF_v2 is ~35-40 % of the bill |
| 3. Production-ready | **~$3,000-4,500+** | zonal nodes, HA data tier, WAF min capacity, Defender, NAT, logs |

## Biggest levers

1. `ingress_mode = internal` removes the App Gateway fixed fee (keep WAF for
   anything internet-facing; Standard_v2 is cheaper than WAF_v2 if WAF is not needed).
2. Stop the dev cluster out of hours: `az aks stop` (no VM charges; managed data
   services keep billing) or scale the user pool to 0 via Terraform `min_count`.
3. Reserved instances / savings plans for production nodes and PostgreSQL.
4. Log Analytics: keep the daily cap in dev, ContainerLogV2 + Basic logs plan for
   high-volume tables, short retention.
5. Burstable PostgreSQL and B0 Redis are fine for the POC; move to GP + HA only in production.

## Live estimate

```bash
python3 scripts/estimate-cost.py --region eastus2 --config dev     # queries https://prices.azure.com
python3 scripts/estimate-cost.py --region eastus2 --config prod --show-meters
```

The script prints every matched meter so the selection can be audited; meters
it cannot match unambiguously are flagged `VERIFY`.
