#!/usr/bin/env python3
"""Monthly cost estimate from the public Azure Retail Prices API.

  python3 scripts/estimate-cost.py --region eastus2 --config dev [--show-meters]

Each line item is a filter on https://prices.azure.com/api/retail/prices
(no authentication). Consumption (pay-as-you-go) prices only; reservations,
savings plans, taxes and support plans are excluded. Usage-based meters (data
processed, log ingestion, transactions) use the stated assumptions. Items whose
filter returns zero or several candidates are flagged VERIFY so the selection is
never silently wrong.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request

API = "https://prices.azure.com/api/retail/prices"
HOURS = 730

# (label, quantity, unit multiplier, OData filter, meter-name contains)
CONFIGS = {
    "dev": [
        ("AKS system node D2ads_v5", 1, HOURS, "serviceName eq 'Virtual Machines' and armSkuName eq 'Standard_D2ads_v5'", "D2ads v5"),
        ("AKS user nodes D4ads_v5", 2, HOURS, "serviceName eq 'Virtual Machines' and armSkuName eq 'Standard_D4ads_v5'", "D4ads v5"),
        ("App Gateway WAF_v2 fixed", 1, HOURS, "serviceName eq 'Application Gateway' and skuName eq 'WAF v2'", "Fixed"),
        ("App Gateway WAF_v2 capacity units (assume 1 CU avg)", 1, HOURS, "serviceName eq 'Application Gateway' and skuName eq 'WAF v2'", "Capacity Units"),
        ("PostgreSQL Flexible B2s compute", 1, HOURS, "serviceName eq 'Azure Database for PostgreSQL' and skuName eq 'B2s'", "B2s"),
        ("PostgreSQL storage (32 GiB)", 32, 1, "serviceName eq 'Azure Database for PostgreSQL' and contains(productName, 'Flexible Server Storage')", "Storage Data Stored"),
        ("Azure Managed Redis Balanced B0", 1, HOURS, "serviceName eq 'Redis Cache' and contains(productName, 'Managed Redis') and contains(skuName, 'B0')", "B0"),
        ("Private endpoints (3)", 3, HOURS, "serviceName eq 'Virtual Network' and contains(productName, 'Private Link')", "Standard Private Endpoint"),
        ("ACR Standard", 30, 1, "serviceName eq 'Container Registry' and skuName eq 'Standard'", "Registry Unit"),
        ("Azure Files Standard LRS hot/TO (20 GiB)", 20, 1, "serviceName eq 'Storage' and contains(productName, 'Files') and skuName eq 'Standard LRS'", "Data Stored"),
        ("Log Analytics ingestion (assume 1.5 GB/day)", 45, 1, "serviceName eq 'Log Analytics' and contains(meterName, 'Data Ingestion')", "Ingestion"),
        ("Public IP (LB outbound)", 1, HOURS, "serviceName eq 'Virtual Network' and contains(productName, 'IP Addresses') and skuName eq 'Standard'", "Static"),
    ],
}
CONFIGS["prod"] = [
    ("AKS Standard tier (uptime SLA)", 1, HOURS, "serviceName eq 'Azure Kubernetes Service' and skuName eq 'Standard'", "Uptime SLA"),
    ("AKS system nodes D4ads_v5", 3, HOURS, "serviceName eq 'Virtual Machines' and armSkuName eq 'Standard_D4ads_v5'", "D4ads v5"),
    ("AKS user nodes D4ads_v5 (avg 4)", 4, HOURS, "serviceName eq 'Virtual Machines' and armSkuName eq 'Standard_D4ads_v5'", "D4ads v5"),
    ("App Gateway WAF_v2 fixed", 1, HOURS, "serviceName eq 'Application Gateway' and skuName eq 'WAF v2'", "Fixed"),
    ("App Gateway WAF_v2 capacity units (min 2 + traffic, assume 4)", 4, HOURS, "serviceName eq 'Application Gateway' and skuName eq 'WAF v2'", "Capacity Units"),
    ("PostgreSQL GP D2ds_v5 (x2 for ZR HA)", 2, HOURS, "serviceName eq 'Azure Database for PostgreSQL' and skuName eq 'D2ds v5'", "vCore"),
    ("PostgreSQL storage 128 GiB (x2 HA)", 256, 1, "serviceName eq 'Azure Database for PostgreSQL' and contains(productName, 'Flexible Server Storage')", "Storage Data Stored"),
    ("Azure Managed Redis Balanced B5 (HA)", 1, HOURS, "serviceName eq 'Redis Cache' and contains(productName, 'Managed Redis') and contains(skuName, 'B5')", "B5"),
    ("Private endpoints (4)", 4, HOURS, "serviceName eq 'Virtual Network' and contains(productName, 'Private Link')", "Standard Private Endpoint"),
    ("ACR Premium", 30, 1, "serviceName eq 'Container Registry' and skuName eq 'Premium'", "Registry Unit"),
    ("Azure Files Standard ZRS (150 GiB)", 150, 1, "serviceName eq 'Storage' and contains(productName, 'Files') and skuName eq 'Standard ZRS'", "Data Stored"),
    ("NAT Gateway", 1, HOURS, "serviceName eq 'Virtual Network' and contains(productName, 'NAT Gateway')", "Gateway"),
    ("Log Analytics ingestion (assume 10 GB/day)", 300, 1, "serviceName eq 'Log Analytics' and contains(meterName, 'Data Ingestion')", "Ingestion"),
    ("Defender for Containers (vCore-hours, 28 vCores)", 28, HOURS, "contains(productName, 'Defender for Containers')", "vCore"),
]


def query(region: str, flt: str) -> list[dict]:
    items, url = [], f"{API}?currencyCode='USD'&$filter=" + urllib.parse.quote(f"armRegionName eq '{region}' and priceType eq 'Consumption' and {flt}")
    while url:
        with urllib.request.urlopen(url, timeout=30) as r:  # noqa: S310 - fixed public endpoint
            page = json.load(r)
        items += page.get("Items", [])
        url = page.get("NextPageLink")
    return items


def pick(items: list[dict], contains: str) -> tuple[dict | None, list[dict]]:
    cands = [i for i in items if contains.lower() in (i["meterName"] + " " + i["skuName"]).lower()
             and "spot" not in i["skuName"].lower() and "low priority" not in i["skuName"].lower()
             and "windows" not in i["productName"].lower()]
    return (cands[0] if len(cands) == 1 else None), cands


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", default="eastus2")
    ap.add_argument("--config", choices=sorted(CONFIGS), default="dev")
    ap.add_argument("--show-meters", action="store_true")
    a = ap.parse_args()
    total, flagged = 0.0, 0
    print(f"{'item':62s} {'unit price':>12s} {'monthly USD':>12s}")
    for label, qty, mult, flt, contains in CONFIGS[a.config]:
        chosen, cands = pick(query(a.region, flt), contains)
        if not chosen:
            flagged += 1
            print(f"{label:62s} {'VERIFY':>12s} {'':>12s}  ({len(cands)} candidate meters)")
            for c in cands[:5]:
                print(f"    - {c['productName']} | {c['skuName']} | {c['meterName']} | {c['retailPrice']} / {c['unitOfMeasure']}")
            continue
        cost = chosen["retailPrice"] * qty * mult
        total += cost
        print(f"{label:62s} {chosen['retailPrice']:12.4f} {cost:12.2f}")
        if a.show_meters:
            print(f"    meter: {chosen['productName']} | {chosen['skuName']} | {chosen['meterName']} | per {chosen['unitOfMeasure']}")
    print(f"{'TOTAL (matched items only)':62s} {'':12s} {total:12.2f}")
    if flagged:
        print(f"{flagged} item(s) need manual verification (see VERIFY lines).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
