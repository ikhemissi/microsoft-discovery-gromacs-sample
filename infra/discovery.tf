resource "azapi_resource" "supercomputer" {
  type      = "Microsoft.Discovery/supercomputers@2026-06-01"
  name      = "sc-${local.resource_suffix}"
  parent_id = azurerm_resource_group.main.id
  location  = var.location
  tags = merge(azurerm_resource_group.main.tags, {
    version                       = "v2"
    "discovery.overridemrgregion" = local.data_plane_location
  })

  body = {
    properties = {
      subnetId = azurerm_subnet.discovery["aksSubnet"].id
      identities = {
        clusterIdentity = { id = azurerm_user_assigned_identity.discovery.id }
        kubeletIdentity = { id = azurerm_user_assigned_identity.discovery.id }
        workloadIdentities = {
          (azurerm_user_assigned_identity.discovery.id) = {}
        }
      }
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }

  depends_on = [azurerm_role_assignment.discovery]
}

resource "azapi_resource" "node_pool" {
  type      = "Microsoft.Discovery/supercomputers/nodePools@2026-06-01"
  name      = "nodepool1"
  parent_id = azapi_resource.supercomputer.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      subnetId         = azurerm_subnet.discovery["supercomputerNodepoolSubnet"].id
      vmSize           = var.node_pool.vm_size
      minNodeCount     = var.node_pool.min_node_count
      maxNodeCount     = var.node_pool.max_node_count
      scaleSetPriority = var.node_pool.scale_set_priority
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }
}

resource "azapi_resource" "workspace" {
  type      = "Microsoft.Discovery/workspaces@2026-06-01"
  name      = "ws-${local.resource_suffix}"
  parent_id = azurerm_resource_group.main.id
  location  = var.location
  tags = merge(azurerm_resource_group.main.tags, {
    version                                    = "v2"
    "discovery.overridemrgregion"              = local.data_plane_location
    "discovery.workbench.enableGhcpAiFeatures" = tostring(var.workspace_features.enable_ghcp_ai_features)
    "discovery.workbench.enableExtensions"     = tostring(var.workspace_features.enable_extensions)
    NetworkIsolation                           = tostring(var.workspace_features.network_isolation)
  })

  body = {
    properties = {
      workspaceIdentity       = { id = azurerm_user_assigned_identity.discovery.id }
      supercomputerIds        = [azapi_resource.supercomputer.id]
      agentSubnetId           = azurerm_subnet.discovery["agentSubnet"].id
      privateEndpointSubnetId = azurerm_subnet.discovery["privateEndpointSubnet"].id
      workspaceSubnetId       = azurerm_subnet.discovery["workspaceSubnet"].id
    }
  }

  timeouts {
    create = "90m"
    update = "90m"
    delete = "90m"
  }

  depends_on = [azapi_resource.node_pool]
}

resource "azapi_resource" "chat_model" {
  type      = "Microsoft.Discovery/workspaces/chatModelDeployments@2026-06-01"
  name      = var.chat_model.deployment_name
  parent_id = azapi_resource.workspace.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      modelFormat = "OpenAI"
      modelName   = var.chat_model.name
    }
  }
}

resource "azapi_resource" "discovery_storage" {
  type      = "Microsoft.Discovery/storageContainers@2026-06-01"
  name      = "stc-${local.resource_suffix}"
  parent_id = azurerm_resource_group.main.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      storageStore = {
        kind             = "AzureStorageBlob"
        storageAccountId = azapi_resource.data_storage.id
      }
    }
  }

  depends_on = [azapi_resource.output_container, azurerm_role_assignment.discovery]
}

resource "azapi_resource" "project" {
  type      = "Microsoft.Discovery/workspaces/projects@2026-06-01"
  name      = "prj-${local.resource_suffix}"
  parent_id = azapi_resource.workspace.id
  location  = var.location
  tags      = azurerm_resource_group.main.tags

  body = {
    properties = {
      storageContainerIds = [azapi_resource.discovery_storage.id]
    }
  }

  depends_on = [azapi_resource.chat_model]
}