variable "global_tags" {
  type        = map(string)
  description = "Tags applied to every taggable project resource; required project and service tags take precedence."
  default     = {}
}

variable "environment_name" {
  type        = string
  description = "The azd environment name used to name and tag resources."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.environment_name))
    error_message = "Use 1-63 alphanumeric characters or hyphens, starting with an alphanumeric character."
  }
}

variable "location" {
  type        = string
  description = "Discovery control-plane region supported by the upstream quickstart."

  validation {
    condition     = contains(["eastus", "swedencentral", "uksouth"], var.location)
    error_message = "Use eastus, swedencentral, or uksouth, as supported by the reference template."
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription in which to provision project resources."
}

variable "assign_provisioner_data_roles" {
  type        = bool
  description = "Assign Discovery Platform Contributor on the resource group and Storage Blob Data Contributor on the outputs container to the Terraform AzureRM authentication principal."
  default     = false
}

variable "data_plane_location" {
  type        = string
  description = "Optional region for networking, identity, storage, and Discovery-managed resources; defaults to location."
  default     = null

  validation {
    condition     = var.data_plane_location == null || var.data_plane_location == "" || contains(["eastus", "swedencentral", "uksouth"], var.data_plane_location)
    error_message = "Use eastus, swedencentral, uksouth, or leave the data-plane region unset."
  }
}

variable "vnet_address_prefix" {
  type        = string
  description = "IPv4 /16 network from which six /24 Discovery subnets are allocated."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vnet_address_prefix)) && can(regex("/16$", var.vnet_address_prefix))
    error_message = "Provide a valid IPv4 /16 CIDR prefix."
  }
}

variable "storage_replication_type" {
  type        = string
  description = "Replication for Discovery data storage, separate from Terraform state storage."
  default     = "GRS"

  validation {
    condition     = contains(["ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Use a zone- or geo-redundant storage replication type: ZRS, GRS, GZRS, RAGRS, or RAGZRS."
  }
}

variable "node_pool" {
  type = object({
    vm_size            = optional(string, "Standard_D4s_v6")
    min_node_count     = optional(number, 0)
    max_node_count     = optional(number, 3)
    scale_set_priority = optional(string, "Regular")
  })
  description = "Discovery node pool configuration; select a GPU SKU explicitly when needed for GROMACS."
  default     = {}

  validation {
    condition = (
      var.node_pool.min_node_count >= 0 &&
      var.node_pool.max_node_count >= 1 &&
      var.node_pool.min_node_count <= var.node_pool.max_node_count &&
      floor(var.node_pool.min_node_count) == var.node_pool.min_node_count &&
      floor(var.node_pool.max_node_count) == var.node_pool.max_node_count
    )
    error_message = "Node counts must be integers with 0 <= min_node_count <= max_node_count and max_node_count >= 1."
  }

  validation {
    condition     = contains(["Regular", "Spot"], var.node_pool.scale_set_priority)
    error_message = "Node pool priority must be Regular or Spot."
  }
}

variable "chat_model" {
  type = object({
    name            = optional(string, "gpt-5.4")
    deployment_name = optional(string, "gpt-5-4")
  })
  description = "OpenAI chat model and deployment name supported by Discovery in the selected region."
  default     = {}

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{3,24}$", var.chat_model.deployment_name)) && length(trimspace(var.chat_model.name)) > 0
    error_message = "Use a non-empty model name and a 3-24 character alphanumeric/hyphen deployment name."
  }
}

variable "workspace_features" {
  type = object({
    enable_ghcp_ai_features = optional(bool, true)
    enable_extensions       = optional(bool, true)
    network_isolation       = optional(bool, true)
  })
  description = "Workspace feature tags; public preview workbench access requires network_isolation=false."
  default     = {}
}