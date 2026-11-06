module "rbac_data" {
  source = "../../../modules/role-assignment"

  assignments = {
    # The Azure Files CSI driver mounts SMB shares as the kubelet identity using
    # Kerberos/SMB OAuth (mountWithManagedIdentity). No storage key exists.
    "kubelet-files-smb-mi-admin" = {
      scope                = module.storage_files.id
      role_definition_name = "Storage File Data SMB MI Admin"
      principal_id         = local.platform.kubelet_identity_principal_id
      description          = "AKS nodes mount Azure Files with managed identity."
    }

    # Personas: browse shared files through the portal/REST with Entra ID (read only).
    "files-reader-devops" = {
      scope                = module.storage_files.id
      role_definition_name = "Storage File Data Privileged Reader"
      principal_id         = local.groups.devops
      principal_type       = "Group"
      description          = "DevOps: read shared files for troubleshooting."
    }
    "files-reader-qa" = {
      scope                = module.storage_files.id
      role_definition_name = "Storage File Data Privileged Reader"
      principal_id         = local.groups.qa
      principal_type       = "Group"
      description          = "QA: verify generated notification files."
    }

    # Data resource visibility (management plane only).
    "rg-data-reader-devops" = {
      scope                = module.rg_data.id
      role_definition_name = "Reader"
      principal_id         = local.groups.devops
      principal_type       = "Group"
    }
    "rg-data-reader-readers" = {
      scope                = module.rg_data.id
      role_definition_name = "Reader"
      principal_id         = local.groups.readers
      principal_type       = "Group"
    }
    "rg-data-monitoring-developers" = {
      scope                = module.rg_data.id
      role_definition_name = "Monitoring Reader"
      principal_id         = local.groups.developers
      principal_type       = "Group"
      description          = "Developers: PostgreSQL/Redis metrics without configuration access."
    }
  }
}
