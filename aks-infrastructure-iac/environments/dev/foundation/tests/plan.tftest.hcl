# Offline plan test: mocked provider, no Azure credentials needed.
# Run: terraform init -backend=false && terraform test
mock_provider "azurerm" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "plan_default_dev" {
  command = plan

  assert {
    condition     = local.subnet_cidrs.aks_nodes == "10.10.0.0/22"
    error_message = "Node subnet must be 10.10.0.0/22."
  }

  assert {
    condition     = local.subnet_cidrs.appgw == "10.10.4.0/24"
    error_message = "App Gateway subnet must be a /24 (AGIC with CNI Overlay)."
  }

  assert {
    condition     = local.subnet_cidrs.postgresql == "10.10.6.0/27"
    error_message = "PostgreSQL delegated subnet must be 10.10.6.0/27."
  }

  assert {
    condition     = local.subnet_cidrs.mgmt == "10.10.7.0/27" && local.subnet_cidrs.bastion == "10.10.7.64/26"
    error_message = "Management and Bastion subnets are misplaced."
  }

  assert {
    condition     = length(module.subnet) == 5
    error_message = "Five subnets expected without Bastion Standard."
  }

  assert {
    condition     = contains(local.private_zones, "akspoc-dev-eus2.private.postgres.database.azure.com")
    error_message = "PostgreSQL private zone missing."
  }
}

run "plan_public_waf_and_nat" {
  command = plan

  variables {
    appgw_public_frontend_enabled   = true
    nat_gateway_enabled             = true
    bastion_standard_subnet_enabled = true
  }

  assert {
    condition     = length(module.subnet) == 6
    error_message = "AzureBastionSubnet expected."
  }

  assert {
    condition     = length(azurerm_nat_gateway.this) == 1
    error_message = "NAT Gateway expected."
  }
}
