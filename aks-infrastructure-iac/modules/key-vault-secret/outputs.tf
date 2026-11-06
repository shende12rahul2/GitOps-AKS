output "id" {
  description = "ARM resource ID of the secret (RBAC scope)."
  value       = local.outputs.secretId.value
}

output "versionless_uri" {
  description = "Versionless secret URI (https://<vault>.vault.azure.net/secrets/<name>)."
  value       = local.outputs.secretUri.value
}

output "name" {
  description = "Secret name."
  value       = var.secret_name
}
