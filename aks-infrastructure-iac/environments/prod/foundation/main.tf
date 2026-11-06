module "naming" {
  source = "../../../modules/naming"

  project         = var.project
  environment     = var.environment
  location_short  = var.location_short
  subscription_id = var.subscription_id
  layer           = "foundation"
  owner           = var.owner
  cost_center     = var.cost_center
}

locals {
  names = module.naming.names
  tags  = module.naming.tags

  # Address plan (see docs/network-design.md). Subnets are carved from the VNet
  # with cidrsubnet so the whole plan follows from a single /16 per environment.
  subnet_cidrs = {
    aks_nodes         = cidrsubnet(var.vnet_cidr, 6, 0)   # x.x.0.0/22   nodes only (pods use the overlay)
    appgw             = cidrsubnet(var.vnet_cidr, 8, 4)   # x.x.4.0/24   App Gateway (AGIC + overlay needs <= /24)
    private_endpoints = cidrsubnet(var.vnet_cidr, 8, 5)   # x.x.5.0/24   Key Vault, Files, Redis, ACR
    postgresql        = cidrsubnet(var.vnet_cidr, 11, 48) # x.x.6.0/27  delegated to PostgreSQL
    mgmt              = cidrsubnet(var.vnet_cidr, 11, 56) # x.x.7.0/27  jumpbox
    bastion           = cidrsubnet(var.vnet_cidr, 10, 29) # x.x.7.64/26 AzureBastionSubnet (Standard SKU only)
  }

  private_zones = concat(
    [
      "privatelink.vaultcore.azure.net",
      "privatelink.file.core.windows.net",
      "privatelink.redis.azure.net",
      local.names.postgres_dns_zone,
      var.app_dns_zone_name,
    ],
    var.acr_private_endpoint_enabled ? ["privatelink.azurecr.io"] : [],
  )

  inbound_from_cluster = [local.subnet_cidrs.aks_nodes, local.subnet_cidrs.mgmt]
}

module "rg_network" {
  source = "../../../modules/resource-group"

  name       = local.names.rg_network
  location   = var.location
  lock_level = var.resource_lock_level
  tags       = local.tags
}

module "vnet" {
  source = "../../../modules/virtual-network"

  name                = local.names.vnet
  location            = var.location
  resource_group_name = module.rg_network.name
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

# --- Network security groups -------------------------------------------------------
module "nsg" {
  source   = "../../../modules/network-security"
  for_each = local.nsg_rules

  name                = "nsg-${module.naming.prefix}-${each.key}"
  location            = var.location
  resource_group_name = module.rg_network.name
  rules               = each.value
  tags                = local.tags
}

locals {
  nsg_rules = {
    "aks-nodes" = {
      # AKS adds its own rules to the NIC-level NSG it manages. The subnet NSG only
      # documents and permits the App Gateway -> pod path used by AGIC.
      AllowAppGatewayToPods = {
        priority                     = 100
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_address_prefixes      = [local.subnet_cidrs.appgw]
        destination_address_prefixes = ["*"]
        destination_port_ranges      = ["*"]
        description                  = "Application Gateway health probes and traffic to pod IPs (AGIC)."
      }
    }

    "appgw" = merge(
      {
        AllowGatewayManager = {
          priority                     = 100
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "Tcp"
          source_address_prefixes      = ["GatewayManager"]
          destination_address_prefixes = ["*"]
          destination_port_ranges      = ["65200-65535"]
          description                  = "App Gateway v2 infrastructure ports."
        }
        AllowAzureLoadBalancer = {
          priority                     = 110
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "*"
          source_address_prefixes      = ["AzureLoadBalancer"]
          destination_address_prefixes = ["*"]
          destination_port_ranges      = ["*"]
        }
        AllowHttpsFromVnet = {
          priority                     = 120
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "Tcp"
          source_address_prefixes      = ["VirtualNetwork"]
          destination_address_prefixes = [local.subnet_cidrs.appgw]
          destination_port_ranges      = ["80", "443"]
          description                  = "Private clients (jumpbox, VPN, peered networks) to the private frontend."
        }
        DenyOtherVnetInbound = {
          priority                     = 4000
          direction                    = "Inbound"
          access                       = "Deny"
          protocol                     = "*"
          source_address_prefixes      = ["VirtualNetwork"]
          destination_address_prefixes = ["*"]
          destination_port_ranges      = ["*"]
        }
      },
      var.appgw_public_frontend_enabled ? {
        AllowHttpsFromInternet = {
          priority                     = 130
          direction                    = "Inbound"
          access                       = "Allow"
          protocol                     = "Tcp"
          source_address_prefixes      = var.appgw_public_source_prefixes
          destination_address_prefixes = ["*"]
          destination_port_ranges      = ["80", "443"]
          description                  = "Public WAF frontend (optional)."
        }
      } : {},
    )

    "private-endpoints" = {
      AllowClusterToPrivateEndpoints = {
        priority                     = 100
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_address_prefixes      = local.inbound_from_cluster
        destination_address_prefixes = [local.subnet_cidrs.private_endpoints]
        destination_port_ranges      = ["443", "445", "10000"]
        description                  = "Key Vault/ACR (443), Azure Files SMB (445), Managed Redis TLS (10000)."
      }
      DenyOtherVnetInbound = {
        priority                     = 4000
        direction                    = "Inbound"
        access                       = "Deny"
        protocol                     = "*"
        source_address_prefixes      = ["VirtualNetwork"]
        destination_address_prefixes = ["*"]
        destination_port_ranges      = ["*"]
      }
    }

    "postgresql" = {
      AllowClusterToPostgres = {
        priority                     = 100
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_address_prefixes      = local.inbound_from_cluster
        destination_address_prefixes = [local.subnet_cidrs.postgresql]
        destination_port_ranges      = ["5432", "6432"]
        description                  = "PostgreSQL (5432) and built-in PgBouncer (6432)."
      }
      DenyOtherVnetInbound = {
        priority                     = 4000
        direction                    = "Inbound"
        access                       = "Deny"
        protocol                     = "*"
        source_address_prefixes      = ["VirtualNetwork"]
        destination_address_prefixes = ["*"]
        destination_port_ranges      = ["*"]
      }
    }

    "mgmt" = {
      AllowBastionDeveloperSsh = {
        priority                     = 100
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_address_prefixes      = ["168.63.129.16"]
        destination_address_prefixes = [local.subnet_cidrs.mgmt]
        destination_port_ranges      = ["22"]
        description                  = "Azure Bastion Developer SKU connects from the Azure platform address."
      }
      AllowBastionStandardSsh = {
        priority                     = 110
        direction                    = "Inbound"
        access                       = "Allow"
        protocol                     = "Tcp"
        source_address_prefixes      = [local.subnet_cidrs.bastion]
        destination_address_prefixes = [local.subnet_cidrs.mgmt]
        destination_port_ranges      = ["22"]
      }
      DenyOtherVnetInbound = {
        priority                     = 4000
        direction                    = "Inbound"
        access                       = "Deny"
        protocol                     = "*"
        source_address_prefixes      = ["VirtualNetwork"]
        destination_address_prefixes = ["*"]
        destination_port_ranges      = ["*"]
      }
    }
  }
}

# --- Optional NAT Gateway (deterministic egress IP, no SNAT port exhaustion) ---------
resource "azurerm_public_ip" "nat" {
  count = var.nat_gateway_enabled ? 1 : 0

  name                = "pip-${local.names.nat_gateway}"
  location            = var.location
  resource_group_name = module.rg_network.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  count = var.nat_gateway_enabled ? 1 : 0

  name                    = local.names.nat_gateway
  location                = var.location
  resource_group_name     = module.rg_network.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = var.nat_gateway_enabled ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# --- Subnets -------------------------------------------------------------------------
module "subnet" {
  source = "../../../modules/subnet"
  for_each = merge(
    {
      "snet-aks-nodes" = {
        cidr       = local.subnet_cidrs.aks_nodes
        nsg        = "aks-nodes"
        delegation = null
        nat        = var.nat_gateway_enabled
        pe_policy  = "Enabled"
      }
      "snet-appgw" = {
        cidr = local.subnet_cidrs.appgw
        nsg  = "appgw"
        # Private-only Application Gateway deployments require this delegation.
        delegation = var.appgw_public_frontend_enabled ? null : {
          name         = "appgw"
          service_name = "Microsoft.Network/applicationGateways"
          actions      = []
        }
        nat       = false
        pe_policy = "Enabled"
      }
      "snet-private-endpoints" = {
        cidr       = local.subnet_cidrs.private_endpoints
        nsg        = "private-endpoints"
        delegation = null
        nat        = false
        pe_policy  = "Enabled" # NSG rules apply to private endpoint traffic
      }
      "snet-postgresql" = {
        cidr = local.subnet_cidrs.postgresql
        nsg  = "postgresql"
        delegation = {
          name         = "postgresql"
          service_name = "Microsoft.DBforPostgreSQL/flexibleServers"
          actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
        nat       = false
        pe_policy = "Enabled"
      }
      "snet-mgmt" = {
        cidr       = local.subnet_cidrs.mgmt
        nsg        = "mgmt"
        delegation = null
        nat        = var.nat_gateway_enabled
        pe_policy  = "Enabled"
      }
    },
    var.bastion_standard_subnet_enabled ? {
      "AzureBastionSubnet" = {
        cidr       = local.subnet_cidrs.bastion
        nsg        = null
        delegation = null
        nat        = false
        pe_policy  = "Enabled"
      }
    } : {},
  )

  name                              = each.key
  resource_group_name               = module.rg_network.name
  virtual_network_name              = module.vnet.name
  address_prefixes                  = [each.value.cidr]
  delegation                        = each.value.delegation
  private_endpoint_network_policies = each.value.pe_policy
  network_security_group            = each.value.nsg == null ? null : { id = module.nsg[each.value.nsg].id }
  nat_gateway                       = each.value.nat ? { id = azurerm_nat_gateway.this[0].id } : null
}

# --- Private DNS -------------------------------------------------------------------
module "private_dns" {
  source = "../../../modules/private-dns"

  resource_group_name = module.rg_network.name
  zone_names          = local.private_zones
  virtual_network_ids = { (local.names.vnet) = module.vnet.id }
  tags                = local.tags
}
