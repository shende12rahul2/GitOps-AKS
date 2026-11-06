terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13"
    }
  }

  # Chicken-and-egg: this configuration creates the remote backend, so it starts
  # with local state. After the first apply, migrate it into the new account:
  #   terraform init -migrate-state -backend-config=backend.hcl
  # (see README.md). Keep the local state file out of Git (.gitignore).
}

provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  storage_use_azuread = true
}
