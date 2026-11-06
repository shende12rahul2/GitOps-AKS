# naming

Resource-free module that returns consistent names and tags for every layer.
Pattern: `<abbreviation>-<project>-<environment>-<region>[-<purpose>]`.
Globally unique names get a 4-character suffix derived from the subscription ID,
so they are deterministic without a random resource in state.

| Resource | Example (project `akspoc`, env `dev`, region `eus2`) |
|---|---|
| Resource groups | `rg-akspoc-dev-eus2-network` / `-platform` / `-data` / `-aks-nodes` |
| AKS | `aks-akspoc-dev-eus2` |
| ACR | `acrakspocdeveus2<sfx>` |
| Key Vault | `kv-akspoc-dev-eus2-<sfx>` |
| PostgreSQL | `psql-akspoc-dev-eus2-<sfx>` |
| Managed Redis | `redis-akspoc-dev-eus2-<sfx>` |
| Storage (files) | `stakspocdeveus2<sfx>` |
| Identities | `id-akspoc-dev-eus2-<workload>` |

<!-- BEGIN GENERATED -->

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11.0 |
| azurerm | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `project` | Short project code (lowercase, 3-8 chars). | `string` |  | yes |
| `environment` | Environment name. | `string` |  | yes |
| `location_short` | Short region code, e.g. eus2. | `string` |  | yes |
| `subscription_id` | Subscription ID (seed for the deterministic uniqueness suffix). | `string` |  | yes |
| `layer` | Lifecycle layer (foundation, platform, data). | `string` |  | yes |
| `owner` | Owning team or contact. | `string` |  | yes |
| `cost_center` | Cost center for chargeback. | `string` |  | yes |
| `extra_tags` | Additional tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `prefix` | Name prefix <project>-<env>-<region>. |
| `suffix` | Deterministic uniqueness suffix. |
| `names` | Map of resource names. |
| `tags` | Standard tags. |
