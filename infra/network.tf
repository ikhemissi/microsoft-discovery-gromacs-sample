locals {
  subnets = {
    supercomputerNodepoolSubnet = { prefix = cidrsubnet(var.vnet_address_prefix, 8, 1), delegation = null, workload = true }
    aksSubnet                   = { prefix = cidrsubnet(var.vnet_address_prefix, 8, 2), delegation = null, workload = true }
    workspaceSubnet             = { prefix = cidrsubnet(var.vnet_address_prefix, 8, 3), delegation = "Microsoft.App/environments", workload = true }
    privateEndpointSubnet       = { prefix = cidrsubnet(var.vnet_address_prefix, 8, 4), delegation = null, workload = false }
    agentSubnet                 = { prefix = cidrsubnet(var.vnet_address_prefix, 8, 5), delegation = "Microsoft.App/environments", workload = true }
    searchSubnet                = { prefix = cidrsubnet(var.vnet_address_prefix, 8, 6), delegation = "Microsoft.App/environments", workload = true }
    # /28 at x.x.7.0 for AKS API Server VNet Integration.
    sc-mgmt = { prefix = cidrsubnet(var.vnet_address_prefix, 12, 112), delegation = "Microsoft.ContainerService/managedClusters", workload = false }
  }

  workload_subnets = { for name, subnet in local.subnets : name => subnet if subnet.workload }
}

resource "azurerm_virtual_network" "discovery" {
  name                = "vnet-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.target_location
  address_space       = [var.vnet_address_prefix]
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_subnet" "discovery" {
  for_each = local.subnets

  name                              = each.key
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.discovery.name
  address_prefixes                  = [each.value.prefix]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"

  dynamic "service_endpoint" {
    for_each = each.value.workload ? ["Microsoft.Storage"] : []

    content {
      service = service_endpoint.value
    }
  }

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]

    content {
      name = replace(delegation.value, "/", ".")

      service_delegation {
        name    = delegation.value
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.target_location
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  ip_version          = "IPv4"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_nat_gateway" "discovery" {
  name                = "nat-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.target_location
  sku_name            = "Standard"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_nat_gateway_public_ip_association" "discovery" {
  nat_gateway_id       = azurerm_nat_gateway.discovery.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Explicit outbound connectivity for workload subnets; private endpoint and sc-mgmt subnets stay without NAT.
resource "azurerm_subnet_nat_gateway_association" "discovery" {
  for_each = local.workload_subnets

  subnet_id      = azurerm_subnet.discovery[each.key].id
  nat_gateway_id = azurerm_nat_gateway.discovery.id

  depends_on = [azurerm_nat_gateway_public_ip_association.discovery]
}
