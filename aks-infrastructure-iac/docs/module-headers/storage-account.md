# storage-account

Hardened storage account for Azure Files:

- Public network access **disabled**; private endpoints per subresource.
- **Shared key access disabled** and **SMB OAuth enabled**: the Azure Files CSI
  driver mounts SMB shares with the kubelet managed identity
  (`mountWithManagedIdentity`), so no account key exists in Kubernetes or Git.
- SMB 3.1.1 only, AES-GCM channel encryption, TLS 1.2, infrastructure encryption.
- Share soft delete (default 7 days).
- File service metrics and write/delete logs to Log Analytics.

Use `account_kind = "FileStorage"` + `account_tier = "Premium"` for NFS or
latency-sensitive workloads (provisioned billing).
