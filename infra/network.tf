locals {
  subnets = {
    supercomputerNodepoolSubnet = { index = 1, delegated = false }
    aksSubnet                   = { index = 2, delegated = false }
    workspaceSubnet             = { index = 3, delegated = true }
    privateEndpointSubnet       = { index = 4, delegated = false }
    agentSubnet                 = { index = 5, delegated = true }
    searchSubnet                = { index = 6, delegated = true }
  }
}

resource "azurerm_virtual_network" "discovery" {
  name                = "vnet-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.data_plane_location
  address_space       = [var.vnet_address_prefix]
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "discovery" {
  for_each = local.subnets

  name                              = each.key
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.discovery.name
  address_prefixes                  = [cidrsubnet(var.vnet_address_prefix, 8, each.value.index)]
  default_outbound_access_enabled   = each.key != "privateEndpointSubnet"
  private_endpoint_network_policies = "Disabled"

  dynamic "service_endpoint" {
    for_each = each.key == "privateEndpointSubnet" ? [] : ["Microsoft.Storage"]

    content {
      service = service_endpoint.value
    }
  }

  dynamic "delegation" {
    for_each = each.value.delegated ? ["Microsoft.App/environments"] : []

    content {
      name = "Microsoft.App.environments"

      service_delegation {
        name    = delegation.value
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}