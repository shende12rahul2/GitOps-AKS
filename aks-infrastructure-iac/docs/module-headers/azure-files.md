# azure-files

Creates Azure file shares (quota, protocol, access tier) on an existing storage
account, plus capacity alerts at a percentage of quota.

**Terraform owns the shares.** Kubernetes consumes them only through statically
provisioned PersistentVolumes managed by Argo CD
(`aks-gitops-deployment/kubernetes/storage`). Dynamic provisioning is never used
for these shares, so the same share is never created by two owners.
