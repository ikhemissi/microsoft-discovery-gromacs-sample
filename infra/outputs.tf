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

output "DISCOVERY_STORAGE_CONTAINER_ID" {
  description = "Discovery storage registration resource ID, distinct from the Azure blob container."
  value       = azapi_resource.discovery_storage.id
}

output "DISCOVERY_PROJECT_ID" {
  description = "Discovery project resource ID."
  value       = azapi_resource.project.id
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