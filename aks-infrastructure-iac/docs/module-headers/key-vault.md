# key-vault

Key Vault with RBAC authorization, purge protection, public network access
disabled (unless `allowed_ip_ranges` is set), a private endpoint and audit logs.

Workloads read secrets through the Key Vault CSI driver using **workload
identity**, with RBAC scoped to individual secrets (`key-vault-secret` module).
