# PostgreSQL design

Azure Database for PostgreSQL Flexible Server 17, private access (VNet
integration), Microsoft Entra ID authentication. No StatefulSet databases.

## Who creates what

| Object | Created by | How |
|---|---|---|
| Server, network, parameters, Entra admins, backups, alerts | Terraform `data` layer | `modules/postgresql` |
| Databases `users_db`, `products_db`, `orders_db`, `airflow_metadata` | `db-bootstrap` Job | `CREATE DATABASE` as the Entra admin |
| Roles: one Entra role per service identity, `airflow` password role, `<db>_readonly`, Entra group roles (non-prod) | `db-bootstrap` Job | `pgaadauth_create_principal_with_oid`, `CREATE/ALTER ROLE` |
| Grants: `REVOKE ALL ON DATABASE ... FROM PUBLIC`, `CONNECT, TEMPORARY` to owner, schema `USAGE, CREATE` | `db-bootstrap` Job | SQL |
| Tables, indexes, seed data, `GRANT SELECT ... TO <db>_readonly` | each service | versioned migrations (`services/<svc>/migrations/NNN_*.sql`) |

Why not Terraform `azurerm_postgresql_flexible_server_database`: databases
created through ARM are owned by an internal administrative role, and the Entra
administrator then cannot create schemas or grant on them. Creating them in SQL
as the Entra admin makes ownership and grants explicit and reviewable.

## Authentication

| Principal | Method | Secret |
|---|---|---|
| user/product/order services | Entra token via workload identity (`DefaultAzureCredential`, scope `https://ossrdbms-aad.database.windows.net/.default`), fetched per new connection | none |
| db-bootstrap | Entra token, server Entra administrator | none |
| Platform admins (group) | Entra token (`az account get-access-token --resource-type oss-rdbms`) | none |
| QA / developers (non-prod) | Entra group roles with `<db>_readonly` | none |
| Airflow | password role `airflow` (SQLAlchemy/Celery cannot refresh tokens) | Key Vault, re-synced each bootstrap run |
| `pgbreakglass` admin | password, **never stored** (ephemeral + write-only) | reset with `az postgres flexible-server update --admin-password` |

Applications never use the administrator. Each service role owns only its own
database's objects and cannot connect to the others (verified: `user-service`
gets `permission denied ... CONNECT` on `orders_db`).

## Connection strings and examples

```text
Service (Entra):  postgresql+psycopg://id-akspoc-dev-eus2-user-service@<server>.akspoc-dev-eus2.private.postgres.database.azure.com:5432/users_db?sslmode=require
                  password = <Entra access token>, injected by svc_common.db on connect
Airflow:          postgresql://airflow:<pw>@<server>...:5432/airflow_metadata?sslmode=require   (Key Vault: airflow-metadata-connection)
Admin (jumpbox):  PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv) \
                  psql "host=<server-fqdn> dbname=postgres user=grp-akspoc-platform-admins sslmode=require"
```

From a pod (diagnostics):

```bash
kubectl -n apps exec deploy/user-service -- python -c "from svc_common.config import CommonSettings as C; from svc_common.db import Database; Database(C(service_name='user-service')).ping(); print('ok')"
```

## Connection pooling

| Tier | Pooling | Budget |
|---|---|---|
| POC (Burstable B2s) | SQLAlchemy pools: services `pool_size=3, max_overflow=2` per replica; Airflow `pool_size=3, max_overflow=5` per process. Built-in PgBouncer is not available on Burstable. | B2s allows ~429 connections; POC peak is well under 150. |
| Production (General Purpose) | Built-in PgBouncer (`pgbouncer.enabled=true`, port 6432, transaction mode) for Airflow and services | size `default_pool_size` per database |

Check: `SELECT usename, count(*) FROM pg_stat_activity GROUP BY 1;`

## Migrations

`python -m svc_common.migrate --dir /app/migrations` (Argo CD Sync hook, wave 0):
applies `NNN_name.sql` files in order, one transaction each, records version +
SHA-256 in `schema_migrations`, fails if an applied file was edited, and holds a
PostgreSQL advisory lock against concurrent runs. Rules: forward-only, new file
per change, backward-compatible with the running version (expand/contract).

## Backup and restore

- Automated backups: daily snapshots + WAL, PITR window 7 days (dev) / 35 days
  (prod), geo-redundant in prod.
- **Restore test** (run quarterly, and before production go-live):

```bash
az postgres flexible-server restore -g rg-akspoc-dev-eus2-data \
  --name psql-restore-test --source-server <server> \
  --restore-time "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
# VNet-integrated servers restore into the same delegated subnet/zone by default.
psql "host=psql-restore-test.<zone> dbname=users_db user=<admin> sslmode=require" -c "select count(*) from users;"
az postgres flexible-server delete -g rg-akspoc-dev-eus2-data -n psql-restore-test --yes
```

- Logical export for long-term retention / migration:
  `pg_dump -Fc -d users_db > users_db-$(date +%F).dump` (jumpbox), stored in a
  separate immutable storage account (production).
