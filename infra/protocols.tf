locals {
  # Must match discovery.data in azure.yaml: <container>/<prefix>/<namespace>/<version>/
  protocol_container = "simulation-protocols"
  protocol_path      = "${local.protocol_container}/experiments/lysozyme-water/v1/"
}

resource "azapi_resource" "protocol_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = local.protocol_container
  parent_id = azapi_update_resource.blob_service.id

  body = {
    properties = { publicAccess = "None" }
  }
}

resource "azapi_resource" "protocol_asset" {
  type      = "Microsoft.Discovery/storageContainers/storageAssets@2026-06-01"
  name      = "lysozyme-protocol-v1"
  parent_id = azapi_resource.discovery_storage.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      description = "Reviewed GROMACS protocol v1 for lysozyme in water: MDP files, prepared structure and checksums."
      path        = local.protocol_path
    }
  }

  depends_on = [azapi_resource.protocol_container]
}

resource "azurerm_role_assignment" "protocol_uploader" {
  scope              = azapi_resource.protocol_container.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  principal_id       = data.azurerm_client_config.acr_publisher.object_id
}
