# private-dns

Creates private DNS zones and links each zone to every VNet in
`virtual_network_ids` (auto-registration disabled). Links are keyed
`<zone>|<vnet key>` for stable identity.

Zones used by this POC:

| Zone | Used by | Mechanism |
|---|---|---|
| `privatelink.vaultcore.azure.net` | Key Vault | Private endpoint |
| `privatelink.file.core.windows.net` | Azure Files | Private endpoint |
| `privatelink.redis.azure.net` | Azure Managed Redis | Private endpoint |
| `<prefix>.private.postgres.database.azure.com` | PostgreSQL Flexible Server | VNet integration (delegated subnet) |
| `privatelink.azurecr.io` | ACR Premium (optional) | Private endpoint |
| `poc.example.com` (configurable) | App/admin hostnames | A records to the ingress IP |
