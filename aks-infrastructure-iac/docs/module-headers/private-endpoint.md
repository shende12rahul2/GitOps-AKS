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
