# Offline test of the platform layer with a mocked provider and a fake
# foundation remote state. `apply` against mocks exercises every count/for_each
# and precondition with realistic unknown/known values.
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "11111111-1111-1111-1111-111111111111"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks"
      oidc_issuer_url = "https://eastus2.oic.prod-aks.azure.com/tenant/guid/"
      ingress_application_gateway = {
        ingress_application_gateway_identity = [{
          object_id                 = "44444444-4444-4444-4444-444444444444"
          client_id                 = "55555555-5555-5555-5555-555555555555"
          user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/agic"
        }]
      }
    }
  }

  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mock"
      principal_id = "22222222-2222-2222-2222-222222222222"
      client_id    = "33333333-3333-3333-3333-333333333333"
      tenant_id    = "11111111-1111-1111-1111-111111111111"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.OperationalInsights/workspaces/log-mock"
    }
  }

  mock_resource "azurerm_monitor_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Monitor/accounts/amw-mock"
    }
  }

  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/actionGroups/ag-mock"
    }
  }

  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.ContainerRegistry/registries/acrmock"
      login_server = "acrmock.azurecr.io"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.KeyVault/vaults/kv-mock"
    }
  }

  mock_resource "azurerm_application_gateway" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/applicationGateways/agw-mock"
    }
  }

  mock_resource "azurerm_web_application_firewall_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/waf-mock"
    }
  }

  mock_resource "azurerm_public_ip" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/publicIPAddresses/pip-mock"
    }
  }

  mock_resource "azurerm_private_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/privateEndpoints/pe-mock"
    }
  }

  mock_resource "azurerm_monitor_data_collection_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/dataCollectionRules/dcr-mock"
    }
  }

  mock_resource "azurerm_monitor_data_collection_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Insights/dataCollectionEndpoints/dce-mock"
    }
  }

  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Compute/virtualMachines/vm-mock"
    }
  }

  mock_resource "azurerm_network_interface" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Network/networkInterfaces/nic-mock"
    }
  }

}

override_data {
  target = data.terraform_remote_state.foundation
  values = {
    outputs = {
      resource_group_name = "rg-akspoc-dev-eus2-network"
      location            = "eastus2"
      vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
      vnet_name           = "vnet-akspoc-dev-eus2"
      subnet_ids = {
        "snet-aks-nodes"         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-aks-nodes"
        "snet-appgw"             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-appgw"
        "snet-private-endpoints" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-private-endpoints"
        "snet-postgresql"        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-postgresql"
        "snet-mgmt"              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-mgmt"
      }
      subnet_cidrs = {
        aks_nodes         = "10.10.0.0/22"
        appgw             = "10.10.4.0/24"
        private_endpoints = "10.10.5.0/24"
        postgresql        = "10.10.6.0/27"
        mgmt              = "10.10.7.0/27"
        bastion           = "10.10.7.64/26"
      }
      private_dns_zone_ids = {
        "privatelink.vaultcore.azure.net"                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        "privatelink.file.core.windows.net"                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
        "privatelink.redis.azure.net"                         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net"
        "akspoc-dev-eus2.private.postgres.database.azure.com" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/pg"
        "poc.example.com"                                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/poc.example.com"
      }
      postgres_dns_zone_name        = "akspoc-dev-eus2.private.postgres.database.azure.com"
      app_dns_zone_name             = "poc.example.com"
      nat_gateway_enabled           = false
      appgw_public_frontend_enabled = false
    }
  }
}

variables {
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  github_organization = "example-org"
}

run "agic_mode" {
  command = apply

  assert {
    condition     = output.ingress_private_ip == "10.10.4.10"
    error_message = "AGIC mode must resolve hostnames to the App Gateway private IP."
  }

  assert {
    condition     = length(module.app_gateway) == 1
    error_message = "App Gateway expected in agic mode."
  }

  assert {
    condition     = length(module.id_workload) == 7
    error_message = "Seven workload identities expected."
  }

  assert {
    condition     = output.hostnames["argocd"] == "argocd.poc.example.com"
    error_message = "Admin hostname mismatch."
  }
}

run "internal_ingress_mode" {
  command = apply

  variables {
    ingress_mode = "internal"
  }

  assert {
    condition     = length(module.app_gateway) == 0
    error_message = "No App Gateway in internal mode (never deploy both ingress paths)."
  }

  assert {
    condition     = output.ingress_private_ip == "10.10.3.232"
    error_message = "Internal mode must use the reserved internal load balancer IP."
  }
}
