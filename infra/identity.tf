resource "azurerm_user_assigned_identity" "discovery" {
  name                = "uami-${local.resource_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.data_plane_location
  isolation_scope     = "Regional"
  tags                = azurerm_resource_group.main.tags
}

resource "azurerm_role_assignment" "discovery" {
  for_each = {
    storage_blob_data_contributor  = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    discovery_platform_contributor = "01288891-85ee-45a7-b367-9db3b752fc65"
    acr_pull                       = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
  }

  scope                            = each.key == "storage_blob_data_contributor" ? azapi_resource.data_storage.id : azurerm_resource_group.main.id
  role_definition_id               = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id                     = azurerm_user_assigned_identity.discovery.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

data "azurerm_client_config" "provisioner" {
  count = var.assign_provisioner_data_roles ? 1 : 0
}

resource "azurerm_role_assignment" "provisioner" {
  for_each = var.assign_provisioner_data_roles ? {
    storage_blob_data_contributor  = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    discovery_platform_contributor = "01288891-85ee-45a7-b367-9db3b752fc65"
  } : {}

  scope              = each.key == "storage_blob_data_contributor" ? azapi_resource.output_container.id : azurerm_resource_group.main.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = data.azurerm_client_config.provisioner[0].object_id
}