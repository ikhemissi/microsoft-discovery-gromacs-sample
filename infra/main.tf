locals {
  resource_suffix     = substr(sha256("${var.subscription_id}/${azurerm_resource_group.main.name}"), 0, 13)
  data_plane_location = coalesce(var.data_plane_location, var.location)
}

resource "azurerm_resource_group" "main" {
  name     = "rg-gromacs-${var.environment_name}"
  location = var.location

  tags = merge(var.global_tags, {
    "azd-env-name" = var.environment_name
    project        = "microsoft-discovery-gromacs-sample"
  })
}