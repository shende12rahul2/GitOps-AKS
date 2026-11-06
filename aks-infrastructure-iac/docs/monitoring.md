# Monitoring and logging

| Signal | Collection | Where |
|---|---|---|
| Container logs (JSON, request IDs) | Container Insights, ContainerLogV2, system namespaces excluded, 5-min interval | Log Analytics |
| Kubernetes events, pod/node inventory | Container Insights | Log Analytics |
| Pod/node metrics, kube-state-metrics | Managed Prometheus (`ama-metrics`) | Azure Monitor workspace |
| Application metrics (`/metrics`: requests, latency) | pod annotations, `platform/monitoring` settings | Azure Monitor workspace |
| Airflow metrics | statsd exporter (annotated) | Azure Monitor workspace |
| Airflow task logs | Azure Files `airflow-logs` (UI) + stdout | Airflow UI / Log Analytics |
| Kubernetes audit | `kube-audit-admin` (writes only), `guard` (Entra auth) | Log Analytics (resource-specific tables) |
| PostgreSQL | `PostgreSQLLogs`, metrics, Query Store (`pg_qs`) | Log Analytics, portal Query Performance Insight |
| Redis | metrics (memory %, connections, ops) | Azure Monitor |
| Storage | file capacity and transactions, write/delete logs | Azure Monitor / Log Analytics |
| App Gateway | access + firewall logs | Log Analytics |
| Key Vault | `AuditEvent` | Log Analytics |

Cost guards: 30-day retention, 2 GB/day cap in dev (data stops being ingested at
the cap; raise or remove in prod), ContainerLogV2 only, `kube-audit-admin` instead
of `kube-audit`, 60-s Prometheus scrape interval.

## Alerts (action group `ag-akspoc-<env>-eus2-critical`)

| Alert | Source | Threshold |
|---|---|---|
| Pod crash looping | Prometheus rule | `CrashLoopBackOff` for 10 min |
| Node not ready | Prometheus rule | 15 min |
| PVC usage | Prometheus rule | > 80 % |
| PostgreSQL CPU / memory / storage | metric alert | > 80 / 90 / 80 % |
| Redis memory | metric alert | > 75 % (NoEviction) |
| File share capacity | metric alert | > 80 % of quota |

## Useful queries (KQL)

```kusto
// Errors per service (last hour)
ContainerLogV2
| where TimeGenerated > ago(1h) and PodNamespace == "apps"
| extend j = parse_json(LogMessage)
| where tostring(j.level) == "ERROR"
| summarize count() by tostring(j.service), bin(TimeGenerated, 5m)

// Trace one request across services
ContainerLogV2 | extend j = parse_json(LogMessage) | where tostring(j.request_id) == "<id>"
| project TimeGenerated, tostring(j.service), tostring(j.message), LogMessage

// WAF blocks
AGWFirewallLogs | where Action == "Blocked" | summarize count() by RuleId, ClientIp

// Who changed what in the cluster
AKSAuditAdmin | where ObjectRef has "apps" | project TimeGenerated, User, Verb, ObjectRef
```
