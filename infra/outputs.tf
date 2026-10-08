output "AZURE_RESOURCE_GROUP" {
  description = "Resource group managed by this azd environment."
  value       = azurerm_resource_group.main.name
}