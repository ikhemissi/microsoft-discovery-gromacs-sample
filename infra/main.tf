resource "azurerm_resource_group" "main" {
  name     = "rg-gromacs-${var.environment_name}"
  location = var.location

  tags = {
    "azd-env-name" = var.environment_name
    project        = "microsoft-discovery-gromacs-sample"
  }
}