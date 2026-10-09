# Microsoft Discovery GROMACS Sample

Microsoft Discovery infrastructure using Azure Developer CLI (`azd`) and Terraform,
translated from the official [Discovery deployment quickstart](https://github.com/Azure/azure-quickstart-templates/tree/9a286202372ff9a9a4f4465e1ef30d7b0f3650c6/quickstarts/microsoft.discovery/discovery-infra-deployment).

- **Infrastructure:** network, managed identity, storage, container registry, supercomputer, node pool,
	workspace, chat model and project. Tool registration and job execution are separate.
- **Experiment:** [lysozyme in water](experiments/lysozyme-water/README.md), an
	educational GROMACS baseline, not a validated formulation study.
- **State:** Azure Blob Storage using your Azure CLI login and Entra authentication,
	without storage keys or service-principal secrets.

## Prerequisites

- Complete the [official Discovery prerequisites](https://learn.microsoft.com/azure/microsoft-discovery/quickstart-infrastructure-portal#prerequisites), including access, roles, provider registration and regional quota.
- Install [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd), [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) and [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5, < 2.0 (>= 1.7 for tests).
- Run commands in Bash from the repository root. State-storage setup requires storage creation and role-assignment permissions.

## Configure Environment

Use the same Azure CLI user and tenant for `azd`. The CLI-auth setting below is global.

```bash
azd config set auth.useAzCliAuth true
az login

SUBSCRIPTION_ID="<subscription-id>"
LOCATION="uksouth"
az account set --subscription "$SUBSCRIPTION_ID"

azd env new dev
azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION_ID"
azd env set AZURE_LOCATION "$LOCATION"
```

Supported regions: `eastus`, `swedencentral`, `uksouth`. Changing an existing
deployment's region can replace resources; always review the preview.

## Discovery Settings

Optional overrides: `azd env set NAME VALUE`.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `DISCOVERY_DATA_PLANE_LOCATION` | Same as `AZURE_LOCATION` | Optional region for networking, identity, storage, and Discovery-managed resources. |
| `DISCOVERY_VNET_ADDRESS_PREFIX` | `10.0.0.0/16` | IPv4 /16; subnet ranges .1 through .6 are allocated as /24s. |
| `DISCOVERY_STORAGE_REPLICATION` | `GRS` | `ZRS`, `GRS`, `GZRS`, `RAGRS`, or `RAGZRS`. |
| `DISCOVERY_VM_SIZE` | `Standard_D4s_v6` | Node pool VM size; this default is CPU-only. |
| `DISCOVERY_MIN_NODES` | `0` | Minimum node count. |
| `DISCOVERY_MAX_NODES` | `3` | Maximum node count, at least 1 and no lower than the minimum. |
| `DISCOVERY_NODE_PRIORITY` | `Regular` | `Regular` or `Spot`. |
| `DISCOVERY_CHAT_MODEL` | `gpt-5.4` | Supported OpenAI model name. |
| `DISCOVERY_CHAT_DEPLOYMENT` | `gpt-5-4` | Chat deployment resource name. |
| `DISCOVERY_ENABLE_GHCP_AI` | `true` | GitHub Copilot and AI workbench feature tag. |
| `DISCOVERY_ENABLE_EXTENSIONS` | `true` | VS Code Marketplace feature tag. |
| `DISCOVERY_NETWORK_ISOLATION` | `true` | Workspace isolation tag. Public preview workbench access requires `false`. |
| `DISCOVERY_ASSIGN_PROVISIONER_DATA_ROLES` | `false` | Assign Discovery and outputs-container data access to the provisioning account. |

Terraform parameters in [infra/main.tfvars.json](infra/main.tfvars.json):

| Parameter | Purpose |
| --- | --- |
| `global_tags` | Map of tags for all taggable Terraform-managed project resources; set to your environment's needs. Required resource tags take precedence. |
| `assign_provisioner_data_roles` | Boolean, default `false`; controlled by `DISCOVERY_ASSIGN_PROVISIONER_DATA_ROLES`. |

Enable provisioning-account data access with:

```bash
azd env set DISCOVERY_ASSIGN_PROVISIONER_DATA_ROLES true
```

This grants **Microsoft Discovery Platform Contributor** on the project resource
group and **Storage Blob Data Contributor** only on the `discoveryoutputs` blob
container. The recipient is Terraform's authenticated AzureRM principal, normally
your Azure CLI user, not the Discovery managed identity. Azure Owner alone does
not grant this data access. Creating the grants requires role-assignment permissions.

If matching grants already exist, import their role-assignment resource IDs into
`azurerm_role_assignment.provisioner["discovery_platform_contributor"]` and
`azurerm_role_assignment.provisioner["storage_blob_data_contributor"]` using the
environment's Terraform backend and with the flag enabled before provisioning;
otherwise Azure can reject duplicate assignments. Once Terraform manages these
grants, setting the flag to `false` removes them on the next provision. Keeping the
flag enabled while changing the authenticated principal replaces the grants.

- Discovery tags are immutable; changing effective tags may require recreation.
- Data storage permits network access but requires Entra authorization; shared-key
	and anonymous access are disabled. Validate Discovery compatibility before restricting its firewall.

## Tool Registry

Terraform creates a billable **Basic** Azure Container Registry in the data-plane
region. Its public endpoint requires Entra authentication; administrator credentials
and anonymous pulls are disabled. The Terraform-authenticated provisioning account
gets registry-scoped **AcrPush**, independently of `assign_provisioner_data_roles`.
Discovery's configured kubelet identity inherits the existing resource-group
**AcrPull** grant. Changing the publishing account replaces its Terraform-managed grant.

Provisioning exports `AZURE_CONTAINER_REGISTRY_NAME`,
`AZURE_CONTAINER_REGISTRY_ENDPOINT`, and `AZURE_CONTAINER_REGISTRY_ID` to azd.
Image publication, tool registration, and simulation execution remain separate steps.
ACR remote builds require additional ACR Tasks permissions; these aren't granted here.

## Bootstrap State Storage

Use an existing accessible Blob container with **Storage Blob Data Contributor**
access, or create a dedicated backend below. It stays outside Terraform management.

```bash
STATE_RESOURCE_GROUP="rg-gromacs-tfstate"
STATE_STORAGE_ACCOUNT="<globally-unique-storage-account-name>"
STATE_CONTAINER="tfstate"
USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

az group create --name "$STATE_RESOURCE_GROUP" --location "$LOCATION"

STATE_ACCOUNT_ID=$(az storage account create \
	--name "$STATE_STORAGE_ACCOUNT" \
	--resource-group "$STATE_RESOURCE_GROUP" \
	--location "$LOCATION" \
	--sku Standard_LRS \
	--kind StorageV2 \
	--https-only true \
	--min-tls-version TLS1_2 \
	--allow-blob-public-access false \
	--allow-shared-key-access false \
	--query id --output tsv)

az role assignment create \
	--assignee-object-id "$USER_OBJECT_ID" \
	--assignee-principal-type User \
	--role "Storage Blob Data Contributor" \
	--scope "$STATE_ACCOUNT_ID"

az storage account blob-service-properties update \
	--account-name "$STATE_STORAGE_ACCOUNT" \
	--resource-group "$STATE_RESOURCE_GROUP" \
	--enable-versioning true \
	--enable-delete-retention true \
	--delete-retention-days 7

az storage container create \
	--name "$STATE_CONTAINER" \
	--account-name "$STATE_STORAGE_ACCOUNT" \
	--auth-mode login \
	--public-access off

azd env set RS_STORAGE_ACCOUNT "$STATE_STORAGE_ACCOUNT"
azd env set RS_CONTAINER_NAME "$STATE_CONTAINER"
```

- Existing backend: run only the two `azd env set` commands with your account/container names.
- The storage firewall must allow your machine. New Blob role assignments may take minutes to propagate.
- Keep backend settings and environment names stable to avoid a state migration.

## Provision And Clean Up

Provisioning creates billable resources, including managed services even when
the workload node pool scales to zero.

```bash
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
azd provision --preview
azd provision
```

- Keep Azure CLI signed in; remove inherited `ARM_ACCESS_KEY`, `ARM_SAS_TOKEN`
	or service-principal credentials so Terraform uses your user login.
- After deployment, open [Discovery Studio](https://studio.discovery.microsoft.com).
	Resource IDs are exported as `DISCOVERY_*_ID` environment values.
- To delete project resources and stored simulation outputs, **back up data first**, then run:

```bash
azd down
```

The separate state backend remains; delete it only when no environments use it.

## Local Validation

Mocked tests validate configuration without deploying resources or requiring Azure credentials.

```bash
terraform -chdir=infra init -backend=false
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra test
```

Tests and previews do not guarantee live regional capacity.

## References

- [Use Terraform with azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/use-terraform-for-azd)
- [Azure Blob backend and Entra authentication](https://developer.hashicorp.com/terraform/language/backend/azurerm)
