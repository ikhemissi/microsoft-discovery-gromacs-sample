locals {
  # Tags from RESOURCE_TAGS ("key=value,key=value"); everything after the first "=" is the value.
  resource_tag_pairs = [for pair in split(",", var.resource_tags) : split("=", pair) if trimspace(pair) != ""]
  resource_tags = {
    for pair in local.resource_tag_pairs : trimspace(pair[0]) => trimspace(join("=", slice(pair, 1, length(pair))))
  }
  resource_suffix     = substr(sha256("${var.subscription_id}/${azurerm_resource_group.main.name}"), 0, 13)
  data_plane_location = coalesce(var.data_plane_location, var.location)
}

resource "azurerm_resource_group" "main" {
  name     = "rg-gromacs-${var.environment_name}"
  location = var.location

  tags = merge(var.global_tags, local.resource_tags, {
    "azd-env-name" = var.environment_name
    project        = "microsoft-discovery-gromacs-sample"
  })
}