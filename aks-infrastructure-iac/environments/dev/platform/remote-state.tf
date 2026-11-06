# Read-only dependency on the foundation layer. The dependency graph between
# layers is strictly one-way: foundation -> platform -> data.
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

locals {
  foundation = data.terraform_remote_state.foundation.outputs
}
