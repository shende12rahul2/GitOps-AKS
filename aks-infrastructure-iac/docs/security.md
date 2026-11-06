# Security

## Controls

| Control | POC | Production additions |
|---|---|---|
| Identity | Entra ID everywhere; workload identity for 7 workloads; GitHub OIDC; no client secrets except Airflow OAuth | Conditional Access for admins, PIM for Owner/Cluster Admin |
| AKS API | private, local accounts disabled, Azure RBAC | API server VNet integration, authorized hub/VPN only |
| Network | private endpoints / VNet integration, NSGs, default-deny NetworkPolicies | Azure Firewall egress with FQDN rules, DDoS Protection on public IP |
| Edge | App Gateway WAF_v2 (DRS 2.1, bot manager, rate limit), TLS 1.2+ policy, HTTP->HTTPS, HSTS | WAF in Prevention everywhere, custom rules, Front Door for global edge |
| Secrets | Key Vault (RBAC, purge protection, private), per-secret RBAC, CSI files (no K8s Secrets for apps), write-only PG admin password | CMK, secret expiry + rotation automation, Key Vault Premium (HSM) for regulated data |
| Workloads | PSS restricted (apps, platform-jobs), non-root 10001, read-only root FS, drop ALL, seccomp RuntimeDefault, no SA token automount | PSS restricted for Airflow, image signing (Notation/cosign + Ratify) |
| Supply chain | digest-only images from ACR (ValidatingAdmissionPolicy), Trivy image/fs/IaC scans, SBOM + provenance attestations, pinned Actions (SHA), Dependabot | ACR Premium quarantine + Defender for Containers, signed images enforced |
| Data | TLS everywhere (PG `require_secure_transport`, Redis 10000, SMB AES-GCM), Entra auth for data access | geo-redundant backups, CMK, private DNS resolver |
| Governance | Deployment Safeguards (Warn), quotas/limit ranges, tags, locks in prod | Azure Policy initiatives (CIS/AKS baseline), Enforce safeguards |
| Detection | audit (kube-audit-admin, guard), Key Vault audit, WAF logs, alerts | Defender for Containers/Key Vault/Storage, Sentinel |
| Delivery | PR reviews, CODEOWNERS, environments, destroy guard, CI cannot reach AKS | signed commits, required approvals on GitOps prod paths |

## Secret inventory and rotation

| Secret | Store | Rotation |
|---|---|---|
| PostgreSQL break-glass admin | nowhere (ephemeral) | bump `administrator_password_version` or `az postgres flexible-server update --admin-password` |
| Airflow DB password | Key Vault `airflow-db-password` + `airflow-metadata-connection` | `terraform apply -replace=random_password.airflow_db`, then sync `db-bootstrap` (ALTER ROLE) and restart Airflow pods |
| Redis access key | Key Vault `airflow-broker-url` | regenerate secondary -> switch -> regenerate primary; re-apply data layer; restart Airflow |
| Internal API key | Key Vault `internal-api-key` | apps accept several keys (one per line): add new, roll, remove old; CSI rotation every 2 min |
| Fernet / API / JWT / webserver keys | Key Vault | Fernet supports `new,old` lists; plan a maintenance window |
| Git-Sync deploy key | Key Vault (operator) | new deploy key -> `set-operator-secret.sh` -> delete old key in GitHub |
| Airflow OAuth client secret | Key Vault (Entra script, 1-year expiry) | re-run `create-app-registrations.sh` before expiry |
| TLS certificates | cert-manager | automatic (90 d, renew at 60 d) |
| Storage keys | disabled | — |

## Validation checklist

- [ ] `az aks show --query "{private:apiServerAccessProfile.enablePrivateCluster, local:disableLocalAccounts, rbac:aadProfile.enableAzureRbac}"` -> true/true/true
- [ ] `nslookup <server>.postgres...`, `<redis>...redis.azure.net`, `<st>.file.core.windows.net`, `<kv>.vault.azure.net` from a pod -> private IPs
- [ ] Public access disabled: Key Vault, Storage, Redis, PostgreSQL (`az ... show --query publicNetworkAccess`)
- [ ] `kubectl -n apps run t --image=nginx` -> rejected (registry/digest policy, PSS)
- [ ] `kubectl -n apps get secrets` as developer -> Forbidden
- [ ] No Kubernetes Secrets in `apps` except cert-manager TLS (`kubectl -n apps get secrets`)
- [ ] NetworkPolicy: from a test pod in `apps`, `curl user-service:8000` blocked unless caller is allowed
- [ ] `curl http://app...` -> 301; `curl -I https://app...` -> `Strict-Transport-Security`
- [ ] WAF: `curl "https://app.../?q=<script>alert(1)</script>"` -> logged (Detection) / 403 (Prevention)
- [ ] Git: `trivy fs --scanners secret .` clean in all three repositories
- [ ] Checkov/TFLint/Trivy green; only reviewed skips (`.checkov.yaml`)

## Checkov skips (reviewed)

See `.checkov.yaml`: each skip is either a false positive (private endpoint in a
sub-module, VNet-integrated PostgreSQL, DRS rule set covering Log4Shell,
AGIC-replaced bootstrap listener) or a documented POC trade-off with the
production setting already present in `environments/prod` (geo-redundant
backups, ZRS, ACR Premium + private endpoint) or listed above (CMK, image signing).
