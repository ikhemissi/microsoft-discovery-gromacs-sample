mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id = "00000000-0000-0000-0000-000000000002"
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
        azurerm_virtual_network.discovery.tags,
        azurerm_user_assigned_identity.discovery.tags,
        azapi_resource.data_storage.tags,
        azapi_resource.supercomputer.tags,
        azapi_resource.node_pool.tags,
        azapi_resource.workspace.tags,
        azapi_resource.chat_model.tags,
        azapi_resource.discovery_storage.tags,
        azapi_resource.project.tags
      ] : try(tags.CostControl == "Ignore" && tags.SecurityControl == "Ignore" && tags.Department == "chemistry", false)
    ])
    error_message = "Every taggable resource must carry the supplied global tags."
  }

  assert {
    condition = (
      length(azurerm_subnet.discovery) == 6 &&
      azurerm_subnet.discovery["supercomputerNodepoolSubnet"].address_prefixes == tolist(["10.0.1.0/24"]) &&
      azurerm_subnet.discovery["searchSubnet"].address_prefixes == tolist(["10.0.6.0/24"]) &&
      length(distinct(flatten([for subnet in azurerm_subnet.discovery : subnet.address_prefixes]))) == 6
    )
    error_message = "The network must contain the six distinct quickstart subnets."
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
      !azurerm_subnet.discovery["privateEndpointSubnet"].default_outbound_access_enabled &&
      length(azurerm_subnet.discovery["privateEndpointSubnet"].service_endpoint) == 0 &&
      alltrue([
        for name, subnet in azurerm_subnet.discovery :
        one(subnet.service_endpoint).service == "Microsoft.Storage" if name != "privateEndpointSubnet"
      ])
    )
    error_message = "Only the five workload subnets must have Storage endpoints; the private endpoint subnet must disable default outbound access."
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
      azapi_resource.project.type == "Microsoft.Discovery/workspaces/projects@2026-06-01"
    )
    error_message = "All six Discovery resources must use the reference API version."
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
      azurerm_virtual_network.discovery.location == "uksouth"
    )
    error_message = "Default compute, model, features, and data-plane region must match the quickstart."
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
    data_plane_location      = "swedencentral"
    vnet_address_prefix      = "10.42.0.0/16"
    storage_replication_type = "ZRS"
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
  }

  assert {
    condition = (
      azapi_resource.workspace.location == "uksouth" &&
      azapi_resource.supercomputer.location == "uksouth" &&
      azurerm_virtual_network.discovery.location == "swedencentral" &&
      azurerm_user_assigned_identity.discovery.location == "swedencentral" &&
      azapi_resource.data_storage.location == "swedencentral" &&
      azapi_resource.workspace.tags["discovery.overridemrgregion"] == "swedencentral" &&
      azapi_resource.supercomputer.tags["discovery.overridemrgregion"] == "swedencentral" &&
      azurerm_subnet.discovery["aksSubnet"].address_prefixes == tolist(["10.42.2.0/24"])
    )
    error_message = "The optional data-plane region and network must propagate without moving Discovery control-plane resources."
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

run "empty_data_plane_region_uses_primary" {
  command = plan

  variables {
    data_plane_location           = ""
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
    condition     = azapi_resource.data_storage.location == "uksouth"
    error_message = "An unset azd data-plane region must fall back to the primary region."
  }
}

run "reject_unsupported_region" {
  command = plan

  variables {
    location = "westeurope"
  }

  expect_failures = [var.location]
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