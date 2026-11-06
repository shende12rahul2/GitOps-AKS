# aks-microservices-app

Five FastAPI microservices, the Airflow image + DAGs, a PostgreSQL bootstrap
tool, and CI that **builds and publishes images but never deploys** (deployment
= a pull request to `aks-gitops-deployment`).

| Service | Routes | Data | Notes |
|---|---|---|---|
| frontend | `/` | — | SSR dashboard; reads notification files from Azure Files; CSRF-protected order form |
| user-service | `/api/users` | PostgreSQL `users_db` | CRUD |
| product-service | `/api/products` | PostgreSQL `products_db` + Redis | cache-aside, TTLs, version-based list invalidation, `X-Cache` header, atomic stock reservation |
| order-service | `/api/orders` | PostgreSQL `orders_db` + Redis | calls user/product/notification services, compensation on failure, batch processing for Airflow |
| notification-service | `/api/notifications` | Azure Files | atomic JSON files, cross-node lock for daily summary |

Common runtime (`libs/svc-common`): environment config, JSON logs with request
IDs, passwordless PostgreSQL (Entra token per connection) and Redis (redis-entraid),
Key Vault CSI file secrets with key rotation, versioned SQL migrations,
health/readiness, Prometheus metrics, security headers (HSTS), shared-storage
helpers and `/api/<svc>/shared/*` endpoints for the cross-node test.
Containers run as UID 10001 with a read-only root filesystem.

## Layout

```
libs/svc-common/            shared runtime + unit tests
services/<service>/         app/, migrations/ (db services), tests/unit, tests/integration, Dockerfile
tools/db-bootstrap/         idempotent databases/roles/grants as the PostgreSQL Entra admin (+ local config)
airflow/                    Dockerfile (official 3.2.2 + providers + plugins), dags/, plugins/aks_poc, tests/
.github/workflows/          test, security-scan, validate-dags, build, update-gitops
.github/images.json         image catalog: Dockerfile, source paths, GitOps file + YAML path
docker-compose.yml          local integration stack (PostgreSQL 17, Redis 8, bootstrap, migrations, 5 services)
```

## Develop

```bash
make venv && . .venv/bin/activate
make lint test             # ruff + all unit tests
make up && make integration   # docker compose stack + integration tests
pip install "apache-airflow[celery,postgres,redis]==3.2.2" -r airflow/requirements.txt \
  --constraint https://raw.githubusercontent.com/apache/airflow/constraints-3.2.2/constraints-3.12.txt
make test-airflow          # DagBag import + DAG policy tests
```

## CI/CD

| Workflow | Trigger | Does |
|---|---|---|
| `test.yml` | PR, main | ruff, unit tests per component, integration job on real PostgreSQL + Redis (bootstrap, migrations x2, 5 services, integration suites) |
| `security-scan.yml` | PR, main, weekly | Trivy (deps, secrets, Dockerfiles), pip-audit, CodeQL |
| `validate-dags.yml` | PR touching `airflow/` | Airflow 3.2.2 with constraints, ruff, DagBag + policies, secret scan |
| `build.yml` | merge to main (changed images) | OIDC to Azure, buildx push with SBOM + provenance, Trivy image scan, digest -> `update-gitops` (dev) |
| `update-gitops.yml` | called by build / manual promotion | copies the digest to test/prod registries (protected environments), opens the GitOps PR |

Required GitHub settings: see [runbook Phase 8](../aks-infrastructure-iac/docs/runbook.md#phase-8---application-build).
Developers need no Azure or cluster write access: they open PRs here; DAGs reach
Airflow through Git-Sync after merge; images reach AKS after the GitOps PR merge.

## Airflow DAGs

`airflow/dags/` is synced by Git-Sync (`ref: main`, `subPath: airflow/dags`).
Python dependencies and shared helpers (`plugins/aks_poc`) are baked into the
Airflow image, never installed by Git-Sync. See
[docs/airflow.md](../aks-infrastructure-iac/docs/airflow.md).
