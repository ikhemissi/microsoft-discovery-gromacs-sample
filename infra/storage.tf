resource "azapi_resource" "data_storage" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = "stg${local.resource_suffix}"
  parent_id = azurerm_resource_group.main.id
  location  = local.data_plane_location
  tags      = azurerm_resource_group.main.tags

  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_${var.storage_replication_type}" }
    properties = {
      accessTier               = "Hot"
      allowBlobPublicAccess    = false
      allowSharedKeyAccess     = false
      minimumTlsVersion        = "TLS1_2"
      supportsHttpsTrafficOnly = true
      networkAcls = {
        defaultAction = "Allow"
        bypass        = "AzureServices"
        virtualNetworkRules = [
          for name, subnet in azurerm_subnet.discovery : {
            id     = subnet.id
            action = "Allow"
          } if name != "privateEndpointSubnet"
        ]
      }
    }
  }
}

resource "azapi_update_resource" "blob_service" {
  type      = "Microsoft.Storage/storageAccounts/blobServices@2023-05-01"
  name      = "default"
  parent_id = azapi_resource.data_storage.id

  body = {
    properties = {
      cors = {
        corsRules = [{
          allowedOrigins = [
            "https://studio.discovery.microsoft.com",
            "https://*.vscode-cdn.net",
            "https://vscode.dev"
          ]
          allowedMethods  = ["GET", "HEAD", "DELETE", "PUT"]
          allowedHeaders  = ["*"]
          exposedHeaders  = ["*"]
          maxAgeInSeconds = 200
        }]
      }
    }
  }
}

resource "azapi_resource" "output_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = "discoveryoutputs"
  parent_id = azapi_update_resource.blob_service.id

  body = {
    properties = { publicAccess = "None" }
  }
}