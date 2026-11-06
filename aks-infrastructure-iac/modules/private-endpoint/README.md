# private-endpoint

Generic private endpoint with a private DNS zone group, so Azure maintains the
A record and clients resolve the service's public FQDN to the private IP.

```hcl
module "pe" {
  source               = "../../../modules/private-endpoint"
  name                 = "pe-kv-akspoc-dev"
  location             = "eastus2"
  resource_group_name  = "rg-akspoc-dev-eus2-platform"
  subnet_id            = local.pe_subnet_id
  target_resource_id   = azurerm_key_vault.this.id
  subresource_name     = "vault"           # file, registry, redisEnterprise, blob, ...
  private_dns_zone_ids = [local.vault_zone_id]
}
```

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Private endpoint name (pe-<service>-<env>). | `string` |  | yes |
| `location` | Azure region (must match the subnet's VNet region). | `string` |  | yes |
| `resource_group_name` | Resource group for the private endpoint. | `string` |  | yes |
| `subnet_id` | Private endpoint subnet ID. | `string` |  | yes |
| `target_resource_id` | Resource ID of the PaaS resource. | `string` |  | yes |
| `subresource_name` | Private link group ID, e.g. vault, file, registry, redisEnterprise. | `string` |  | yes |
| `private_dns_zone_ids` | Private DNS zone IDs for the zone group. | `list(string)` |  | yes |
| `tags` | Resource tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `id` | Private endpoint ID. |
| `private_ip_address` | Private IP allocated to the endpoint NIC. |
