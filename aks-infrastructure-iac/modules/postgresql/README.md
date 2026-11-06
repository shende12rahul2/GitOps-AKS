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

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Server name (globally unique, 3-63 lowercase chars). | `string` |  | yes |
| `location` | Azure region. | `string` |  | yes |
| `resource_group_name` | Resource group. | `string` |  | yes |
| `tenant_id` | Entra tenant ID. | `string` |  | yes |
| `postgresql_version` | Major PostgreSQL version. | `string` | `17` | no |
| `sku_name` | Compute SKU: B_Standard_B2s (POC), GP_Standard_D2ds_v5 (production, built-in PgBouncer). | `string` | `B_Standard_B2s` | no |
| `zone` | Availability zone for the primary (null = no preference). | `string` | `1` | no |
| `high_availability_mode` | null (POC), SameZone or ZoneRedundant (production). Not available on Burstable. | `string` | `null` | no |
| `delegated_subnet_id` | Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. | `string` |  | yes |
| `private_dns_zone_id` | Private DNS zone ending in .postgres.database.azure.com, linked to the VNet. | `string` |  | yes |
| `storage_mb` | Storage size in MB (32768 = 32 GiB, smallest). | `number` | `32768` | no |
| `storage_tier` | Premium SSD performance tier for the disk (P4 for 32 GiB). | `string` | `P4` | no |
| `backup_retention_days` | Point-in-time restore window (7-35 days). | `number` | `7` | no |
| `geo_redundant_backup_enabled` | Geo-redundant backups (set at creation; production DR). | `bool` | `false` | no |
| `administrator_login` | Break-glass password administrator login. | `string` | `pgbreakglass` | no |
| `administrator_password_version` | Increment to rotate the (discarded) break-glass password. | `number` | `1` | no |
| `entra_administrators` | Map of key => Entra administrator (identity or group). | `map(object({object_id = string, principal_name = string, ...` |  | yes |
| `pgbouncer_enabled` | Enable the built-in PgBouncer on port 6432 (General Purpose / Memory Optimized only). | `bool` | `false` | no |
| `server_parameters` | Additional server parameters (override defaults). | `map(string)` | `{}` | no |
| `log_analytics_workspace_id` | Log Analytics workspace for logs and metrics. | `string` | `null` | no |
| `action_group_id` | Action group for alerts (used when alerts_enabled = true). | `string` | `null` | no |
| `tags` | Resource tags. | `map(string)` | `{}` | no |
| `diagnostics_enabled` | Send diagnostics to log_analytics_workspace_id. A separate flag (not a null check) keeps count known at plan time when the workspace is created in the same apply. | `bool` | `false` | no |
| `alerts_enabled` | Create metric alerts routed to action_group_id (explicit flag keeps count known at plan time). | `bool` | `false` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Server ID. |
| `name` | Server name. |
| `fqdn` | Server FQDN (private). |
| `port` | Direct port 5432; built-in PgBouncer uses 6432. |
