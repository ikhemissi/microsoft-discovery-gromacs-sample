output "AZURE_RESOURCE_GROUP" {
  description = "Resource group managed by this azd environment."
  value       = azurerm_resource_group.main.name
}

output "AZURE_CONTAINER_REGISTRY_NAME" {
  description = "Project-owned registry for Discovery tool images."
  value       = azurerm_container_registry.tools.name
}

output "AZURE_CONTAINER_REGISTRY_ENDPOINT" {
  description = "Login server used to tag and publish Discovery tool images."
  value       = azurerm_container_registry.tools.login_server
}

output "AZURE_CONTAINER_REGISTRY_ID" {
  description = "Registry resource ID for image publishing and access checks."
  value       = azurerm_container_registry.tools.id
}

output "DISCOVERY_SUPERCOMPUTER_ID" {
  description = "Discovery Supercomputer resource ID."
  value       = azapi_resource.supercomputer.id
}

output "DISCOVERY_NODE_POOL_ID" {
  description = "Discovery node pool resource ID."
  value       = azapi_resource.node_pool.id
}

output "DISCOVERY_WORKSPACE_ID" {
  description = "Discovery Workspace resource ID."
  value       = azapi_resource.workspace.id
}

output "DISCOVERY_CHAT_MODEL_ID" {
  description = "Discovery chat model deployment resource ID."
  value       = azapi_resource.chat_model.id
}

output "DISCOVERY_CHAT_MODEL_DEPLOYMENT_NAME" {
  description = "Existing Discovery chat model deployment name for agents."
  value       = azapi_resource.chat_model.name
}

output "DISCOVERY_STORAGE_CONTAINER_ID" {
  description = "Discovery storage registration resource ID, distinct from the Azure blob container."
  value       = azapi_resource.discovery_storage.id
}

output "DISCOVERY_PROJECT_ID" {
  description = "Discovery project resource ID."
  value       = azapi_resource.project.id
}

output "DISCOVERY_BOOKSHELF_ID" {
  description = "Discovery Bookshelf resource ID; knowledge-base creation and indexing are separate operations."
  value       = azapi_resource.bookshelf.id
}

output "DISCOVERY_BOOKSHELF_NAME" {
  description = "Discovery Bookshelf name used by the azd knowledge-base service."
  value       = azapi_resource.bookshelf.name
}

output "DISCOVERY_KNOWLEDGE_BLOB_CONTAINER_ID" {
  description = "Blob container holding knowledge-base documents uploaded by the azd extension."
  value       = azapi_resource.knowledge_container.id
}

output "DISCOVERY_KNOWLEDGE_ASSET_ID" {
  description = "Discovery storage asset for the lysozyme-in-water research documents."
  value       = azapi_resource.knowledge_asset.id
}

output "DISCOVERY_INDEX_NODE_POOL_ID" {
  description = "Memory-optimized node pool used for knowledge-base indexing."
  value       = azapi_resource.index_node_pool.id
}

output "DISCOVERY_PROTOCOL_BLOB_CONTAINER_ID" {
  description = "Blob container holding simulation protocol bundles uploaded by the azd extension."
  value       = azapi_resource.protocol_container.id
}

output "DISCOVERY_PROTOCOL_ASSET_ID" {
  description = "Discovery storage asset for the lysozyme-in-water protocol v1 bundle."
  value       = azapi_resource.protocol_asset.id
}

output "DISCOVERY_MANAGED_IDENTITY_ID" {
  description = "User-assigned managed identity used by Discovery."
  value       = azurerm_user_assigned_identity.discovery.id
}

output "DISCOVERY_STORAGE_ACCOUNT_ID" {
  description = "Discovery data storage account resource ID, not Terraform state storage."
  value       = azapi_resource.data_storage.id
}

output "DISCOVERY_VNET_ID" {
  description = "Virtual network containing the six Discovery subnets."
  value       = azurerm_virtual_network.discovery.id
}