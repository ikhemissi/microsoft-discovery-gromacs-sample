terraform {
  required_version = ">= 1.5, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }

  backend "azurerm" {
    use_azuread_auth = true
    use_cli          = true
    use_oidc         = false
    use_msi          = false
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  use_cli         = true

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
  use_cli         = true
}