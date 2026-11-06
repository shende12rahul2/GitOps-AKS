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
