# Offline test of the data layer (mocked provider, fake remote states).
mock_provider "azurerm" {

  mock_resource "azurerm_postgresql_flexible_server" {
    defaults = {
      id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-mock"
      fqdn = "psql-mock.akspoc-dev-eus2.private.postgres.database.azure.com"
    }
  }

  mock_resource "azurerm_managed_redis" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Cache/redisEnterprise/redis-mock"
      hostname = "redis-mock.eastus2.redis.azure.net"
      default_database = {
        port               = 10000
        primary_access_key = "abc+def/ghi=="
      }
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Storage/storageAccounts/stmock"
    }
  }

  mock_resource "azurerm_storage_share" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Storage/storageAccounts/stmock/fileServices/default/shares/share"
    }
  }

  mock_resource "azurerm_resource_group_template_deployment" {
    defaults = {
      id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.Resources/deployments/kvsecret"
      output_content = "{\"secretId\":{\"type\":\"String\",\"value\":\"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock/providers/Microsoft.KeyVault/vaults/kv-mock/secrets/s\"},\"secretUri\":{\"type\":\"String\",\"value\":\"https://kv-mock.vault.azure.net/secrets/s\"}}"
    }
  }
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


override_data {
  target = data.terraform_remote_state.platform
  values = {
    outputs = {
      tenant_id                     = "11111111-1111-1111-1111-111111111111"
      resource_group_name           = "rg-akspoc-dev-eus2-platform"
      key_vault_name                = "kv-akspoc-dev-eus2-abcd"
      log_analytics_workspace_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/log"
      action_group_id               = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Insights/actionGroups/ag"
      kubelet_identity_principal_id = "66666666-6666-6666-6666-666666666666"
      entra_group_object_ids = {
        platform_admins = "00000000-0000-0000-0000-000000000001"
        devops          = "00000000-0000-0000-0000-000000000002"
        developers      = "00000000-0000-0000-0000-000000000003"
        qa              = "00000000-0000-0000-0000-000000000004"
        readers         = "00000000-0000-0000-0000-000000000005"
      }
      workload_identities = {
        for k in ["frontend", "user-service", "product-service", "order-service", "notification-service", "airflow", "db-bootstrap"] :
        k => { name = "id-akspoc-dev-eus2-${k}", client_id = "33333333-3333-3333-3333-333333333333", principal_id = "22222222-2222-2222-2222-222222222222" }
      }
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "data_layer" {
  command = apply

  assert {
    condition     = length(module.secret) == 8 && length(module.operator_secret) == 3
    error_message = "Expected 8 Terraform-managed and 3 operator-managed Key Vault secrets."
  }

  assert {
    condition     = output.redis_port == 10000
    error_message = "Managed Redis TLS port must be 10000."
  }

  assert {
    condition     = startswith(nonsensitive(local.managed_secret_values["airflow-broker-url"]), "rediss://:abc%2Bdef%2Fghi%3D%3D@redis-mock.eastus2.redis.azure.net:10000/0")
    error_message = "Broker URL must use rediss:// with a URL-encoded access key."
  }

  assert {
    condition     = length(nonsensitive(local.managed_secret_values["airflow-fernet-key"])) == 44 && !strcontains(nonsensitive(local.managed_secret_values["airflow-fernet-key"]), "+")
    error_message = "Fernet key must be 32 bytes in URL-safe base64 (44 chars)."
  }

  assert {
    condition     = toset(output.file_share_names) == toset(["shared-files", "airflow-logs"])
    error_message = "Shares shared-files and airflow-logs expected."
  }
}
