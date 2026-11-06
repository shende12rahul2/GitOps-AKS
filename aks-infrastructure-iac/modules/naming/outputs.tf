output "prefix" {
  description = "Name prefix <project>-<env>-<region>."
  value       = local.prefix
}

output "suffix" {
  description = "Deterministic uniqueness suffix."
  value       = local.suffix
}

output "names" {
  description = "Map of resource names."
  value       = local.names
}

output "tags" {
  description = "Standard tags."
  value       = local.tags
}
