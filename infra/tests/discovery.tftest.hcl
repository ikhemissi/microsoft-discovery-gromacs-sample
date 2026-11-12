mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }

  # azapi parents and NAT associations validate Azure resource ID formats.
  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/subnet-test"
    }
  }

  mock_resource "azurerm_nat_gateway" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Network/natGateways/nat-test"
    }
  }

  mock_resource "azurerm_public_ip" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Network/publicIPAddresses/pip-nat-test"
    }
  }
}
mock_provider "azapi" {}

variables {
  environment_name = "test"
  location         = "uksouth"
  subscription_id  = "00000000-0000-0000-0000-000000000001"
  global_tags = {
    CostControl     = "Ignore"
    SecurityControl = "Ignore"
    Department      = "chemistry"
  }
}

run "quickstart_defaults" {
  command = plan

  assert {
    condition = (
      !var.assign_provisioner_data_roles &&
      length(azurerm_role_assignment.provisioner) == 0 &&
      length(data.azurerm_client_config.provisioner) == 0
    )
    error_message = "Provisioner data-role assignments and identity lookup must be disabled by default."
  }

  assert {
    condition = alltrue([
      for tags in [
        azurerm_resource_group.main.tags,
        azurerm_container_registry.tools.tags,
        azurerm_virtual_network.discovery.tags,
        azurerm_public_ip.nat.tags,
        azurerm_nat_gateway.discovery.tags,
        azurerm_user_assigned_identity.discovery.tags,
        azapi_resource.data_storage.tags,
        azapi_resource.supercomputer.tags,
        azapi_resource.node_pool.tags,
        azapi_resource.workspace.tags,
        azapi_resource.chat_model.tags,
        azapi_resource.discovery_storage.tags,
        azapi_resource.bookshelf.tags,
        azapi_resource.project.tags
      ] : try(tags.CostControl == "Ignore" && tags.SecurityControl == "Ignore" && tags.Department == "chemistry", false)
    ])
    error_message = "Every taggable resource must carry the supplied global tags."
  }

  assert {
    condition = (
      azurerm_container_registry.tools.sku == "Basic" &&
      !azurerm_container_registry.tools.admin_enabled &&
      !azurerm_container_registry.tools.anonymous_pull_enabled &&
      azurerm_container_registry.tools.public_network_access_enabled &&
      azurerm_container_registry.tools.role_assignment_mode == "LegacyRegistryPermissions" &&
      azurerm_container_registry.tools.location == "uksouth"
    )
    error_message = "The tools registry must use Basic SKU, authenticated RBAC access, and the target region."
  }

  assert {
    condition = (
      length(azurerm_subnet.discovery) == 7 &&
      azurerm_subnet.discovery["supercomputerNodepoolSubnet"].address_prefixes == tolist(["10.0.1.0/24"]) &&
      azurerm_subnet.discovery["searchSubnet"].address_prefixes == tolist(["10.0.6.0/24"]) &&
      azurerm_subnet.discovery["sc-mgmt"].address_prefixes == tolist(["10.0.7.0/28"]) &&
      azurerm_subnet.discovery["sc-mgmt"].delegation[0].service_delegation[0].name == "Microsoft.ContainerService/managedClusters" &&
      length(distinct(flatten([for subnet in azurerm_subnet.discovery : subnet.address_prefixes]))) == 7
    )
    error_message = "The network must contain the six quickstart subnets and the delegated /28 management subnet."
  }

  assert {
    condition = alltrue([
      for name in ["workspaceSubnet", "agentSubnet", "searchSubnet"] :
      azurerm_subnet.discovery[name].delegation[0].service_delegation[0].name == "Microsoft.App/environments"
    ])
    error_message = "Workspace, agent, and search subnets must be delegated to Microsoft.App/environments."
  }

  assert {
    condition = (
      alltrue([for subnet in azurerm_subnet.discovery : !subnet.default_outbound_access_enabled]) &&
      length(azurerm_subnet.discovery["privateEndpointSubnet"].service_endpoint) == 0 &&
      length(azurerm_subnet.discovery["sc-mgmt"].service_endpoint) == 0 &&
      alltrue([
        for name, subnet in azurerm_subnet.discovery :
        one(subnet.service_endpoint).service == "Microsoft.Storage" if !contains(["privateEndpointSubnet", "sc-mgmt"], name)
      ])
    )
    error_message = "Every subnet must disable default outbound access; only the five workload subnets get Storage endpoints."
  }

  assert {
    condition = (
      toset(keys(azurerm_subnet_nat_gateway_association.discovery)) == toset([
        "supercomputerNodepoolSubnet", "aksSubnet", "workspaceSubnet", "agentSubnet", "searchSubnet"
      ]) &&
      azurerm_nat_gateway.discovery.sku_name == "Standard" &&
      azurerm_public_ip.nat.sku == "Standard" &&
      azurerm_public_ip.nat.allocation_method == "Static" &&
      azurerm_nat_gateway.discovery.location == "uksouth" &&
      azurerm_public_ip.nat.location == "uksouth"
    )
    error_message = "Only the five workload subnets must use the NAT gateway for explicit outbound connectivity."
  }

  assert {
    condition = (
      azapi_resource.data_storage.body.sku.name == "Standard_GRS" &&
      !azapi_resource.data_storage.body.properties.allowSharedKeyAccess &&
      !azapi_resource.data_storage.body.properties.allowBlobPublicAccess &&
      azapi_resource.data_storage.body.properties.supportsHttpsTrafficOnly &&
      azapi_resource.data_storage.body.properties.minimumTlsVersion == "TLS1_2" &&
      azapi_resource.data_storage.body.properties.networkAcls.defaultAction == "Allow" &&
      length(azapi_resource.data_storage.body.properties.networkAcls.virtualNetworkRules) == 5 &&
      azapi_resource.output_container.body.properties.publicAccess == "None"
    )
    error_message = "Data storage must preserve the keyless, private-blob, TLS and Discovery control-plane compatibility settings."
  }

  assert {
    condition = (
      toset(azapi_update_resource.blob_service.body.properties.cors.corsRules[0].allowedOrigins) == toset([
        "https://studio.discovery.microsoft.com", "https://*.vscode-cdn.net", "https://vscode.dev"
      ]) &&
      azurerm_user_assigned_identity.discovery.isolation_scope == "Regional" &&
      length(azurerm_role_assignment.discovery) == 3 &&
      endswith(azurerm_role_assignment.discovery["discovery_platform_contributor"].role_definition_id, "/01288891-85ee-45a7-b367-9db3b752fc65")
    )
    error_message = "The Discovery identity, RBAC, and browser CORS prerequisites must match the quickstart."
  }

  assert {
    condition = (
      azapi_resource.supercomputer.type == "Microsoft.Discovery/supercomputers@2026-06-01" &&
      azapi_resource.node_pool.type == "Microsoft.Discovery/supercomputers/nodePools@2026-06-01" &&
      azapi_resource.workspace.type == "Microsoft.Discovery/workspaces@2026-06-01" &&
      azapi_resource.chat_model.type == "Microsoft.Discovery/workspaces/chatModelDeployments@2026-06-01" &&
      azapi_resource.discovery_storage.type == "Microsoft.Discovery/storageContainers@2026-06-01" &&
      azapi_resource.bookshelf.type == "Microsoft.Discovery/bookshelves@2026-06-01" &&
      azapi_resource.project.type == "Microsoft.Discovery/workspaces/projects@2026-06-01"
    )
    error_message = "All seven Discovery resources must use the reference API version."
  }

  assert {
    condition = (
      azapi_resource.node_pool.body.properties.vmSize == "Standard_D4s_v6" &&
      azapi_resource.node_pool.body.properties.minNodeCount == 0 &&
      azapi_resource.node_pool.body.properties.maxNodeCount == 3 &&
      azapi_resource.chat_model.body.properties.modelName == "gpt-5.4" &&
      azapi_resource.chat_model.body.properties.modelFormat == "OpenAI" &&
      azapi_resource.workspace.tags.NetworkIsolation == "true" &&
      azapi_resource.workspace.tags["discovery.workbench.enableGhcpAiFeatures"] == "true" &&
      azapi_resource.workspace.tags["discovery.workbench.enableExtensions"] == "true" &&
      azapi_resource.workspace.tags["discovery.overridemrgregion"] == "uksouth" &&
      azapi_resource.supercomputer.tags["discovery.overridemrgregion"] == "uksouth" &&
      !contains(keys(azapi_resource.workspace.tags), "SkipAssociateKeyVaultToNsp") &&
      !contains(keys(azapi_resource.supercomputer.tags), "SkipAssociateKeyVaultToNsp") &&
      azurerm_virtual_network.discovery.location == "uksouth"
    )
    error_message = "Default compute, model, features, and single-region placement must match the quickstart."
  }
}

run "bookshelf_configuration" {
  command   = apply
  state_key = "bookshelf"

  plan_options {
    target = [azapi_resource.bookshelf]
  }

  override_resource {
    target = azurerm_resource_group.main
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test"
    }
  }

  override_resource {
    target = azapi_resource.data_storage
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest"
    }
  }

  override_resource {
    target = azapi_update_resource.blob_service
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest/blobServices/default"
    }
  }

  override_resource {
    target = azapi_resource.output_container
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest/blobServices/default/containers/discoveryoutputs"
    }
  }

  assert {
    condition = (
      azapi_resource.bookshelf.parent_id == azurerm_resource_group.main.id &&
      azapi_resource.bookshelf.location == "uksouth" &&
      azapi_resource.bookshelf.body.properties.customerManagedKeys == "Disabled" &&
      azapi_resource.bookshelf.body.properties.publicNetworkAccess == "Enabled" &&
      azapi_resource.bookshelf.body.properties.privateEndpointSubnetId == azurerm_subnet.discovery["privateEndpointSubnet"].id &&
      azapi_resource.bookshelf.body.properties.searchSubnetId == azurerm_subnet.discovery["searchSubnet"].id &&
      keys(azapi_resource.bookshelf.body.properties.workloadIdentities) == [azurerm_user_assigned_identity.discovery.id] &&
      azapi_resource.bookshelf.tags.indexSize == "small" &&
      azapi_resource.bookshelf.tags.NetworkIsolation == "true" &&
      output.DISCOVERY_BOOKSHELF_ID == azapi_resource.bookshelf.id
    )
    error_message = "The bookshelf must reuse the Discovery network and identity, default to Studio-reachable public access and small sizing, and export its resource ID."
  }
}

run "assign_provisioner_data_roles_with_azd_string_input" {
  command = apply

  plan_options {
    target = [azurerm_role_assignment.provisioner]
  }

  variables {
    assign_provisioner_data_roles = "true"
  }

  override_resource {
    target = azurerm_resource_group.main
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test"
    }
  }

  override_resource {
    target = azapi_resource.data_storage
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest"
    }
  }

  override_resource {
    target = azapi_update_resource.blob_service
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest/blobServices/default"
    }
  }

  override_resource {
    target = azapi_resource.output_container
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest/blobServices/default/containers/discoveryoutputs"
    }
  }

  assert {
    condition = (
      var.assign_provisioner_data_roles &&
      length(azurerm_role_assignment.provisioner) == 2 &&
      length(data.azurerm_client_config.provisioner) == 1 &&
      alltrue([
        for assignment in azurerm_role_assignment.provisioner :
        assignment.principal_id == "00000000-0000-0000-0000-000000000002"
      ])
    )
    error_message = "Enabling the azd flag must assign exactly two roles to the authenticated provisioner."
  }

  assert {
    condition = (
      azurerm_role_assignment.provisioner["discovery_platform_contributor"].scope == azurerm_resource_group.main.id &&
      azurerm_role_assignment.provisioner["discovery_platform_contributor"].role_definition_id == "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/01288891-85ee-45a7-b367-9db3b752fc65" &&
      azurerm_role_assignment.provisioner["storage_blob_data_contributor"].scope == azapi_resource.output_container.id &&
      azurerm_role_assignment.provisioner["storage_blob_data_contributor"].role_definition_id == "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    )
    error_message = "Provisioner roles must use the approved resource-group and container scopes."
  }
}

run "cross_region_gpu_and_azd_string_inputs" {
  command = plan

  variables {
    target_location               = "westus3"
    skip_keyvault_nsp_association = "true"
    vnet_address_prefix           = "10.42.0.0/16"
    storage_replication_type      = "ZRS"
    node_pool = {
      vm_size            = "Standard_NC24ads_A100_v4"
      min_node_count     = "1"
      max_node_count     = "2"
      scale_set_priority = "Spot"
    }
    workspace_features = {
      network_isolation       = "false"
      enable_ghcp_ai_features = "false"
      enable_extensions       = "false"
    }
    bookshelf_public_network_access = "Disabled"
  }

  assert {
    condition = (
      azurerm_resource_group.main.location == "uksouth" &&
      alltrue([
        for location in [
          azapi_resource.workspace.location,
          azapi_resource.supercomputer.location,
          azapi_resource.node_pool.location,
          azapi_resource.chat_model.location,
          azapi_resource.discovery_storage.location,
          azapi_resource.bookshelf.location,
          azapi_resource.project.location
        ] : location == "uksouth"
      ]) &&
      alltrue([
        for location in [
          azurerm_container_registry.tools.location,
          azurerm_virtual_network.discovery.location,
          azurerm_user_assigned_identity.discovery.location,
          azapi_resource.data_storage.location,
          azurerm_nat_gateway.discovery.location,
          azurerm_public_ip.nat.location
        ] : location == "westus3"
      ]) &&
      alltrue([
        for tags in [
          azapi_resource.workspace.tags,
          azapi_resource.supercomputer.tags,
          azapi_resource.bookshelf.tags
        ] : tags["discovery.overridemrgregion"] == "westus3" && tags.SkipAssociateKeyVaultToNsp == "true"
      ]) &&
      azapi_resource.bookshelf.tags.NetworkIsolation == "false" &&
      azapi_resource.bookshelf.body.properties.publicNetworkAccess == "Disabled" &&
      azurerm_subnet.discovery["aksSubnet"].address_prefixes == tolist(["10.42.2.0/24"]) &&
      azurerm_subnet.discovery["sc-mgmt"].address_prefixes == tolist(["10.42.7.0/28"])
    )
    error_message = "Target-region resources must move to the target region while Discovery control-plane resources stay in the home region."
  }

  assert {
    condition = (
      azapi_resource.node_pool.body.properties.vmSize == "Standard_NC24ads_A100_v4" &&
      azapi_resource.node_pool.body.properties.minNodeCount == 1 &&
      azapi_resource.node_pool.body.properties.maxNodeCount == 2 &&
      azapi_resource.node_pool.body.properties.scaleSetPriority == "Spot" &&
      azapi_resource.workspace.tags.NetworkIsolation == "false" &&
      azapi_resource.workspace.tags["discovery.workbench.enableGhcpAiFeatures"] == "false" &&
      azapi_resource.workspace.tags["discovery.workbench.enableExtensions"] == "false" &&
      azapi_resource.data_storage.body.sku.name == "Standard_ZRS"
    )
    error_message = "azd string inputs must become typed node counts and workspace flags."
  }
}

run "empty_target_region_uses_home_region" {
  command = plan

  variables {
    target_location               = ""
    assign_provisioner_data_roles = "false"
  }

  assert {
    condition = (
      length(azurerm_role_assignment.provisioner) == 0 &&
      length(data.azurerm_client_config.provisioner) == 0
    )
    error_message = "An explicit false azd flag must disable provisioner roles and identity lookup."
  }

  assert {
    condition = (
      azapi_resource.data_storage.location == "uksouth" &&
      azapi_resource.workspace.tags["discovery.overridemrgregion"] == "uksouth"
    )
    error_message = "An unset azd target region must fall back to the home region."
  }
}

run "reject_unsupported_region" {
  command = plan

  variables {
    location = "westeurope"
  }

  expect_failures = [var.location]
}

run "reject_target_region_as_home_region" {
  command = plan

  variables {
    location = "westus3"
  }

  expect_failures = [var.location]
}

run "reject_unsupported_target_region" {
  command = plan

  variables {
    target_location = "westus2"
  }

  expect_failures = [var.target_location]
}

run "reject_target_region_without_ai_search_features" {
  command = plan

  variables {
    target_location = "norwayeast"
  }

  expect_failures = [var.target_location]
}

run "reject_display_name_target_region" {
  command = plan

  variables {
    target_location = "West US 3"
  }

  expect_failures = [var.target_location]
}

run "reject_invalid_node_counts" {
  command = plan

  variables {
    node_pool = { min_node_count = 4, max_node_count = 3 }
  }

  expect_failures = [var.node_pool]
}

run "reject_fractional_node_count" {
  command = plan

  variables {
    node_pool = { max_node_count = 1.5 }
  }

  expect_failures = [var.node_pool]
}

run "reject_undersized_network" {
  command = plan

  variables {
    vnet_address_prefix = "10.0.0.0/24"
  }

  expect_failures = [var.vnet_address_prefix]
}

run "registry_publisher_and_discovery_pull_access" {
  command = apply

  plan_options {
    target = [azurerm_role_assignment.acr_publisher, azurerm_role_assignment.discovery["acr_pull"]]
  }

  override_resource {
    target = azurerm_resource_group.main
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test"
    }
  }

  override_resource {
    target = azurerm_container_registry.tools
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.ContainerRegistry/registries/acrtest"
    }
  }

  override_resource {
    target = azurerm_user_assigned_identity.discovery
    values = {
      principal_id = "00000000-0000-0000-0000-000000000003"
    }
  }

  assert {
    condition = (
      azurerm_role_assignment.acr_publisher.scope == azurerm_container_registry.tools.id &&
      azurerm_role_assignment.acr_publisher.principal_id == "00000000-0000-0000-0000-000000000002" &&
      endswith(azurerm_role_assignment.acr_publisher.role_definition_id, "/8311e382-0749-4cb8-b61a-304f252e45ec") &&
      azurerm_role_assignment.discovery["acr_pull"].scope == azurerm_resource_group.main.id &&
      azurerm_role_assignment.discovery["acr_pull"].principal_id == "00000000-0000-0000-0000-000000000003" &&
      endswith(azurerm_role_assignment.discovery["acr_pull"].role_definition_id, "/7f951dda-4ed3-4680-a7ca-43fe172d538d")
    )
    error_message = "The provisioner must get registry-scoped AcrPush and Discovery must retain inherited AcrPull."
  }

  assert {
    condition = (
      output.AZURE_CONTAINER_REGISTRY_NAME == azurerm_container_registry.tools.name &&
      output.AZURE_CONTAINER_REGISTRY_ENDPOINT == azurerm_container_registry.tools.login_server &&
      output.AZURE_CONTAINER_REGISTRY_ID == azurerm_container_registry.tools.id
    )
    error_message = "azd must receive the registry name, login server, and resource ID for publishing."
  }
}

run "supercomputer_management_subnet" {
  command   = apply
  state_key = "supercomputer_management_subnet"

  plan_options {
    target = [azapi_resource.supercomputer]
  }

  override_resource {
    target = azapi_resource.supercomputer
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Discovery/supercomputers/sc-test"
    }
  }

  override_resource {
    target = azapi_resource.data_storage
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Storage/storageAccounts/stgtest"
    }
  }

  override_resource {
    target = azurerm_subnet.discovery["aksSubnet"]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/aksSubnet"
    }
  }

  override_resource {
    target = azurerm_subnet.discovery["sc-mgmt"]
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-gromacs-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/sc-mgmt"
    }
  }

  assert {
    condition = (
      endswith(azapi_resource.supercomputer.body.properties.subnetId, "/subnets/aksSubnet") &&
      endswith(azapi_resource.supercomputer.body.properties.managementSubnetId, "/subnets/sc-mgmt") &&
      length(azurerm_subnet_nat_gateway_association.discovery) == 5
    )
    error_message = "The supercomputer must use the AKS subnet, the sc-mgmt subnet for API Server VNet Integration, and wait for NAT outbound connectivity."
  }
}
