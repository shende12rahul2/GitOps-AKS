output "id" {
  description = "AKS cluster ID (scope for Azure RBAC Kubernetes role assignments)."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  description = "OIDC issuer used by workload identity federated credentials."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "private_fqdn" {
  description = "Private API server FQDN."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "node_resource_group" {
  description = "AKS-managed node resource group."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "node_resource_group_id" {
  description = "Node resource group ID."
  value       = azurerm_kubernetes_cluster.this.node_resource_group_id
}

output "current_kubernetes_version" {
  description = "Resolved Kubernetes patch version."
  value       = azurerm_kubernetes_cluster.this.current_kubernetes_version
}

output "key_vault_secrets_provider_identity" {
  description = "Identity created by the Key Vault CSI add-on (unused: workloads use workload identity)."
  value       = try(azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0], null)
}

output "agic_identity_object_id" {
  description = "Object ID of the AGIC add-on identity (null when AGIC is disabled)."
  value       = try(azurerm_kubernetes_cluster.this.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id, null)
}
