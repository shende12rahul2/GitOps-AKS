# Persona RBAC for the platform layer (see docs/rbac-matrix.md).
#
# Kubernetes authorization uses Azure RBAC for Kubernetes (role assignments at
# cluster scope or "<cluster id>/namespaces/<ns>") combined with Kubernetes RBAC
# RoleBindings to Entra group object IDs (GitOps kubernetes/rbac). Nobody except
# platform administrators can read Secrets; deployments go through Git and Argo CD.
locals {
  aks_id = module.aks.id
  ns     = { for n in ["apps", "airflow", "argocd"] : n => "${module.aks.id}/namespaces/${n}" }

  persona_assignments = {
    # Everyone who uses kubectl needs the user credential (kubelogin) first.
    "aks-user-platform-admins" = { scope = local.aks_id, role = "Azure Kubernetes Service Cluster User Role", group = "platform_admins" }
    "aks-user-devops"          = { scope = local.aks_id, role = "Azure Kubernetes Service Cluster User Role", group = "devops" }
    "aks-user-developers"      = { scope = local.aks_id, role = "Azure Kubernetes Service Cluster User Role", group = "developers" }
    "aks-user-qa"              = { scope = local.aks_id, role = "Azure Kubernetes Service Cluster User Role", group = "qa" }
    "aks-user-readers"         = { scope = local.aks_id, role = "Azure Kubernetes Service Cluster User Role", group = "readers" }

    "aks-cluster-admin-platform-admins" = { scope = local.aks_id, role = "Azure Kubernetes Service RBAC Cluster Admin", group = "platform_admins" }

    # DevOps: read everything (no Secrets), operate (restart, scale, exec) in workload namespaces.
    "aks-reader-devops"         = { scope = local.aks_id, role = "Azure Kubernetes Service RBAC Reader", group = "devops" }
    "aks-writer-devops-apps"    = { scope = local.ns.apps, role = "Azure Kubernetes Service RBAC Writer", group = "devops" }
    "aks-writer-devops-airflow" = { scope = local.ns.airflow, role = "Azure Kubernetes Service RBAC Writer", group = "devops" }

    # Developers and QA: read-only in workload namespaces (pods, logs, events). No Secrets, no exec.
    "aks-reader-developers-apps"    = { scope = local.ns.apps, role = "Azure Kubernetes Service RBAC Reader", group = "developers" }
    "aks-reader-developers-airflow" = { scope = local.ns.airflow, role = "Azure Kubernetes Service RBAC Reader", group = "developers" }
    "aks-reader-qa-apps"            = { scope = local.ns.apps, role = "Azure Kubernetes Service RBAC Reader", group = "qa" }
    "aks-reader-qa-airflow"         = { scope = local.ns.airflow, role = "Azure Kubernetes Service RBAC Reader", group = "qa" }

    # Read-only users: cluster-wide read (no Secrets).
    "aks-reader-readers" = { scope = local.aks_id, role = "Azure Kubernetes Service RBAC Reader", group = "readers" }

    # Registry.
    "acr-pull-devops"     = { scope = module.acr.id, role = "AcrPull", group = "devops" }
    "acr-pull-developers" = { scope = module.acr.id, role = "AcrPull", group = "developers" }

    # Key Vault: values only for platform admins/DevOps; metadata for read-only users.
    "kv-officer-platform-admins" = { scope = module.key_vault.id, role = "Key Vault Secrets Officer", group = "platform_admins" }
    "kv-officer-devops"          = { scope = module.key_vault.id, role = "Key Vault Secrets Officer", group = "devops" }
    "kv-reader-readers"          = { scope = module.key_vault.id, role = "Key Vault Reader", group = "readers" }

    # Logs and metrics.
    "logs-reader-devops"     = { scope = module.monitoring.log_analytics_workspace_id, role = "Log Analytics Reader", group = "devops" }
    "logs-reader-developers" = { scope = module.monitoring.log_analytics_workspace_id, role = "Log Analytics Reader", group = "developers" }
    "logs-reader-qa"         = { scope = module.monitoring.log_analytics_workspace_id, role = "Log Analytics Reader", group = "qa" }
    "logs-reader-readers"    = { scope = module.monitoring.log_analytics_workspace_id, role = "Log Analytics Reader", group = "readers" }
    "monitoring-reader-all"  = { scope = module.rg_platform.id, role = "Monitoring Reader", group = "readers" }

    # Resource group visibility (changes go through Terraform pull requests).
    "rg-reader-devops"     = { scope = module.rg_platform.id, role = "Reader", group = "devops" }
    "rg-reader-developers" = { scope = module.rg_platform.id, role = "Reader", group = "developers" }
    "rg-reader-qa"         = { scope = module.rg_platform.id, role = "Reader", group = "qa" }
    "rg-reader-readers"    = { scope = module.rg_platform.id, role = "Reader", group = "readers" }
  }
}

module "rbac_personas" {
  source = "../../../modules/role-assignment"

  assignments = {
    for k, a in local.persona_assignments : k => {
      scope                = a.scope
      role_definition_name = a.role
      principal_id         = local.groups[a.group]
      principal_type       = "Group"
      description          = "Persona ${a.group}: ${a.role}"
    }
  }
}
