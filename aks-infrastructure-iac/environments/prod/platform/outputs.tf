output "resource_group_name" {
  description = "Platform resource group."
  value       = module.rg_platform.name
}

output "resource_group_id" {
  description = "Platform resource group ID."
  value       = module.rg_platform.id
}

output "tenant_id" {
  description = "Entra tenant ID."
  value       = local.tenant_id
}

output "aks_name" {
  description = "AKS cluster name."
  value       = module.aks.name
}

output "aks_id" {
  description = "AKS cluster ID."
  value       = module.aks.id
}

output "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer (for app registration federated credentials, e.g. Argo CD SSO)."
  value       = module.aks.oidc_issuer_url
}

output "aks_private_fqdn" {
  description = "Private API server FQDN."
  value       = module.aks.private_fqdn
}

output "kubelet_identity_principal_id" {
  description = "Kubelet identity principal (Azure Files managed-identity mounts)."
  value       = module.id_aks_kubelet.principal_id
}

output "kubelet_identity_client_id" {
  description = "Kubelet identity client ID."
  value       = module.id_aks_kubelet.client_id
}

output "acr_id" {
  description = "ACR ID."
  value       = module.acr.id
}

output "acr_login_server" {
  description = "ACR login server."
  value       = module.acr.login_server
}

output "key_vault_id" {
  description = "Key Vault ID."
  value       = module.key_vault.id
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.key_vault.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID."
  value       = module.monitoring.log_analytics_workspace_id
}

output "action_group_id" {
  description = "Critical alert action group."
  value       = module.monitoring.action_group_id
}

output "workload_identities" {
  description = "Workload identities: name (PostgreSQL role), client ID (service account annotation), principal ID."
  value = {
    for k, m in module.id_workload : k => {
      name         = m.name
      client_id    = m.client_id
      principal_id = m.principal_id
    }
  }
}

output "github_acr_identity_client_id" {
  description = "Client ID for the application CI (GitHub variable AZURE_CLIENT_ID in aks-microservices-app)."
  value       = module.id_github_acr.client_id
}

output "ingress_mode" {
  description = "agic or internal."
  value       = var.ingress_mode
}

output "ingress_private_ip" {
  description = "Private IP of the single ingress entry point."
  value       = local.ingress_private_ip
}

output "app_gateway_name" {
  description = "App Gateway name (null in internal mode)."
  value       = try(module.app_gateway[0].name, null)
}

output "app_gateway_public_ip" {
  description = "Public IP when the optional public frontend is enabled."
  value       = try(module.app_gateway[0].public_ip_address, null)
}

output "hostnames" {
  description = "Fully qualified application and admin hostnames."
  value       = { for h in var.ingress_hostnames : h => "${h}.${local.foundation.app_dns_zone_name}" }
}

output "entra_group_object_ids" {
  description = "Persona groups (re-used by the data layer)."
  value       = var.entra_group_object_ids
}
