# Validation report

What was actually executed while building this POC (2026-11-06), with which
tool versions, and what can only be verified in a real Azure subscription. No
Azure resources were deployed from the build environment.

## Executed and passing

### Terraform (`aks-infrastructure-iac`)

| Check | Tooling | Result |
|---|---|---|
| `terraform validate`, all 10 roots (bootstrap + 3 layers x 3 envs) | Terraform 1.17.1, azurerm 5.13.0, random 3.9.1 | valid |
| Real provider schema | `terraform providers schema` of azurerm 5.13.0; caught v5 changes (DNS link/record arguments, `node_provisioning_profile`, `rbac_authorization_enabled`, `public_network_access`) | fixed |
| Offline plan/apply with mocked provider (`terraform test`) | dev foundation (2 runs), platform (`agic` + `internal` ingress modes), data; also run against **prod** tfvars | all pass |
| Assertions | CIDR plan; 7 workload identities; ingress IP per mode; no App Gateway in internal mode; 8 managed + 3 operator secrets; URL-encoded Redis key in `rediss://` broker URL; URL-safe 44-char Fernet key | pass |
| Plan-time safety | every `count`/`for_each` known at plan time (boolean toggles; objects for optional IDs); no sensitive values in `for_each` | pass |
| `terraform fmt -check`, environment parity script | | pass |
| TFLint 0.65.0 (terraform ruleset, `preset = all`) | azurerm ruleset not installable offline (runs in CI) | 0 issues |
| Checkov 3.4.3 | 80 passed, 0 failed; skips reviewed one by one in `.checkov.yaml`; AKS module parse issue (`for` attribute) isolated to the alert-rule file | pass |
| Destroy guard, changed-roots matrix | synthetic plan JSON / temp git repo | behave as designed |
| Provider lock files | 4 platforms (h1 hashes) | committed |

### Application (`aks-microservices-app`)

| Check | Result |
|---|---|
| ruff lint + format (rules E,F,W,I,B,UP,S,BLE,SIM,RUF) | clean |
| Unit tests: svc-common 10, frontend 3, user 5, product 6, order 6, notification 4, db-bootstrap 2 | **36 passed** |
| **Integration on real PostgreSQL 16 + Redis** (local packages): db-bootstrap (run twice, idempotent), migrations as each service's own role (re-run no-op), five services under uvicorn, integration suites | **4/4 suites pass** |
| Least privilege on real PostgreSQL | QA role: SELECT ok, DELETE denied; user-service cannot CONNECT to orders_db; airflow role can create tables |
| Redis behaviour | keys namespaced `app:<svc>:...`, every key has a TTL; Celery keys `airflow:...` |
| Cross-service shared files | notification files written by one service read and rendered by the frontend; request IDs propagated in JSON logs |
| Airflow DAG tests (Airflow **3.2.2**, official constraints) | DagBag: 0 import errors, policies, 9 tests pass |
| `airflow db migrate` as the bootstrap-created `airflow` role | success |
| `airflow dags test order_processing_pipeline` against the live services | **success, 9/9 task instances** |
| `airflow dags test shared_storage_check` | **success, 6/6** |
| **CeleryExecutor end to end**: api-server + scheduler + dag-processor + Celery worker, broker Redis with `maxmemory-policy noeviction`, `global_keyprefix=airflow:`, results in PostgreSQL | DAG runs `success`, tasks executed by the Celery worker |
| DAG change pickup (Git-Sync equivalent: file changed under the DAGs folder) | new version visible in ~5 s |
| Celery provider TLS logic (3.20.0 as pinned by Airflow 3.2.2, and 3.26.0) | `ssl_active=True` + `ssl_mutual_tls=False` -> `ssl_cert_reqs=CERT_REQUIRED`, system CAs |

### GitOps (`aks-gitops-deployment`)

| Check | Result |
|---|---|
| `helm lint --strict` five service charts; 12 platform charts x 3 environments | 5/5, 36/36 |
| Render every environment exactly like Argo CD (`scripts/render.py`), including the **official Airflow 1.22.0**, **Argo CD 10.14.0** and **Traefik 42.3.0** charts with these values | 18 applications per environment (19 in internal mode) |
| kubeconform 0.8.0, strict, Kubernetes 1.36, CRD schemas (Argo CD, cert-manager, Secrets Store, Traefik) | dev 180/180, test 177/177, prod 187/187 valid (CRD objects themselves skipped) |
| Internal ingress variant (Traefik, internal LB 10.10.3.232) | 194 valid; NetworkPolicies switch to the ingress namespace |
| Chart guardrails | rendering fails without digest, with tag-as-digest, with `LoadBalancer`, with `privileged: true` |
| Rendered Airflow config | CeleryExecutor, TLS broker, `airflow:` prefix, Key Vault-sourced secrets, no bundled Redis/PostgreSQL, Git-Sync `ref: main`, no default admin user |
| GitHub SSH host keys in Git-Sync `knownHosts` | match GitHub's published SHA256 fingerprints |
| yamllint on environments and values | clean |

## Not executed here (needs Azure, GitHub or Docker)

| Item | Why | How to verify |
|---|---|---|
| `terraform plan/apply` against Azure | no subscription in the build environment | runbook Phases 2-5 |
| Azure Managed Redis specifics: TLS on 10000, NoCluster with Kombu, Entra auth via redis-entraid | needs the service | runbook Phase 7 (`celery inspect ping`, DAG run), product-service `/healthz/ready` |
| PostgreSQL Entra functions (`pgaadauth_create_principal_with_oid`) and grants on the `azure_pg_admin`-owned `public` schema | needs Flexible Server | `db-bootstrap` Job logs; fallback: set `schema: app` per database in the bootstrap config |
| Azure Files managed-identity SMB mount | needs AKS + storage | `validate-shared-storage.sh` |
| AGIC behaviour (path maps, probes, TLS upload) | needs App Gateway | `show-backend-health`, smoke test |
| Container image builds and Trivy image scans | no Docker daemon | `build.yml` |
| GitHub Actions workflows themselves | not run on GitHub; YAML parsed, actions pinned to resolved commit SHAs | first PRs in each repository |
| kind admission-policy tests | no Docker daemon | `validate.yml` job `policy-tests` |
| cert-manager chart rendering | chart repository unreachable from the build environment | `validate.yml` pulls it |
| Live prices | Azure Retail Prices API unreachable from the build environment | `scripts/estimate-cost.py` |
