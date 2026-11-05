locals {
  resource_suffix = substr(sha256("${var.subscription_id}/${azurerm_resource_group.main.name}"), 0, 13)
  target_location = coalesce(var.target_location, var.location)

  # Applied to Discovery resources that support the managed resource group region override.
  mrg_override_tags = merge(
    { "discovery.overridemrgregion" = local.target_location },
    var.skip_keyvault_nsp_association ? { SkipAssociateKeyVaultToNsp = "true" } : {}
  )
}

resource "azurerm_resource_group" "main" {
  name     = "rg-gromacs-${var.environment_name}"
  location = var.location

  tags = merge(var.global_tags, {
    "azd-env-name" = var.environment_name
    project        = "microsoft-discovery-gromacs-sample"
  })
}