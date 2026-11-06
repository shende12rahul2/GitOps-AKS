# postgresql

Azure Database for PostgreSQL Flexible Server with **private access (VNet
integration)**: the server is injected into a delegated subnet and resolves via
a private DNS zone ending in `.postgres.database.azure.com`. No public endpoint.

- **Entra ID authentication** with Entra administrators (the db-bootstrap
  workload identity and the platform admin group).
- **Password admin is break-glass only**: its password comes from an
  `ephemeral "random_password"` and is sent write-only
  (`administrator_password_wo`). It is never stored in state or anywhere else.
  Rotate/recover with `az postgres flexible-server update --admin-password`.
- Password auth stays enabled only for the Airflow metadata role.
- Server parameters: TLS 1.2+, `require_secure_transport`, connection logging,
  slow-query logging, Query Store, optional built-in PgBouncer (GP/MO tiers only,
  validated by a `precondition`).
- Automated backups with configurable PITR window and optional geo-redundancy.
- CPU, memory and storage alerts.

**Databases are intentionally not created here.** Databases created through ARM
are owned by an internal role, so the Entra administrator cannot create schemas
or grant privileges in them. The versioned `db-bootstrap` Job in the GitOps repo
creates databases, roles and grants in SQL (see `docs/database.md`).
