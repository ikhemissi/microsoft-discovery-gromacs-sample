resource "azurerm_container_registry" "tools" {
  name                          = "acr${local.resource_suffix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = local.data_plane_location
  sku                           = "Basic"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  role_assignment_mode          = "LegacyRegistryPermissions"
  tags                          = azurerm_resource_group.main.tags
}

data "azurerm_client_config" "acr_publisher" {}

resource "azurerm_role_assignment" "acr_publisher" {
  scope              = azurerm_container_registry.tools.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/8311e382-0749-4cb8-b61a-304f252e45ec"
  principal_id       = data.azurerm_client_config.acr_publisher.object_id
}