data "terraform_remote_state" "foundation" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "foundation.tfstate"
    use_azuread_auth     = true
  }
}

data "terraform_remote_state" "platform" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "platform.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  foundation = data.terraform_remote_state.foundation.outputs
  platform   = data.terraform_remote_state.platform.outputs
  wi         = local.platform.workload_identities
  groups     = local.platform.entra_group_object_ids
}
