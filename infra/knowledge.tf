locals {
  # Must match discovery.data in azure.yaml: <container>/<prefix>/<namespace>/<version>/
  knowledge_container = "bookshelf-docs"
  knowledge_path      = "${local.knowledge_container}/research/lysozyme-water/v1/"
}

resource "azapi_resource" "knowledge_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = local.knowledge_container
  parent_id = azapi_update_resource.blob_service.id

  body = {
    properties = { publicAccess = "None" }
  }
}

resource "azapi_resource" "knowledge_asset" {
  type      = "Microsoft.Discovery/storageContainers/storageAssets@2026-06-01"
  name      = "lysozyme-water-v1"
  parent_id = azapi_resource.discovery_storage.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      description = "Open-access research papers on hen egg-white lysozyme in water, indexed by the Bookshelf."
      path        = local.knowledge_path
    }
  }

  depends_on = [azapi_resource.knowledge_container]
}

resource "azurerm_role_assignment" "knowledge_uploader" {
  scope              = azapi_resource.knowledge_container.id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  principal_id       = data.azurerm_client_config.acr_publisher.object_id
}

resource "azapi_resource" "index_node_pool" {
  type      = "Microsoft.Discovery/supercomputers/nodePools@2026-06-01"
  name      = "indexpool"
  parent_id = azapi_resource.supercomputer.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      subnetId         = azurerm_subnet.discovery["supercomputerNodepoolSubnet"].id
      vmSize           = var.index_node_pool.vm_size
      minNodeCount     = var.index_node_pool.min_node_count
      maxNodeCount     = var.index_node_pool.max_node_count
      scaleSetPriority = "Regular"
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }

  depends_on = [azapi_resource.node_pool]
}
