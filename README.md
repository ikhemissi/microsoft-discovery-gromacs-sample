# Microsoft Discovery GROMACS Sample

Microsoft Discovery infrastructure using Azure Developer CLI (`azd`) and Terraform,
translated from the official [Discovery deployment quickstart](https://github.com/Azure/azure-quickstart-templates/tree/9a286202372ff9a9a4f4465e1ef30d7b0f3650c6/quickstarts/microsoft.discovery/discovery-infra-deployment).
The reference revision is `9a286202372ff9a9a4f4465e1ef30d7b0f3650c6`, using the
`Microsoft.Discovery` API version `2026-06-01`.

The deployment creates:

- An environment-specific resource group and a virtual network with six /24 subnets.
- A regional user-assigned managed identity with Storage Blob Data Contributor on
	the data account, and Discovery Platform Contributor and AcrPull on the resource group.
- A separate Discovery data storage account, browser CORS settings, and a private
	`discoveryoutputs` blob container, with shared-key and anonymous access disabled.
- A Discovery Supercomputer and configurable node pool.
- A Discovery Workspace, OpenAI chat model deployment, storage registration, and project.

AzureRM manages networking, identity, and RBAC. AzAPI manages Discovery resources
and Storage ARM resources, including blob settings, without requiring the deploying
user to have Blob data access on the Discovery data account. Resources managed
internally by the Discovery service are not separately managed by Terraform.
Terraform does not install GROMACS, register tools, or launch simulation jobs.

All taggable Terraform resources and the state-storage bootstrap use
`CostControl=Ignore` and `SecurityControl=Ignore`, as required by this tenant's
policy opt-out convention. These tags are not Azure Policy exemptions by
themselves; the tenant policies must honor them. Discovery-managed resources
are created by the service and must be checked separately for tag propagation.

Terraform state is stored in Azure Blob Storage and accessed using the signed-in
user's Microsoft Entra identity through Azure CLI. No storage account keys, SAS
tokens, or service principal secrets are required.

## Prerequisites

- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 and < 2.0.
- Terraform >= 1.7 is required to run the offline mocked tests.
- Bash for the commands below, run from the repository root.
- Permission to create resource groups and storage accounts in the subscription.
	The state-storage bootstrap also requires permission to assign Azure roles
	(for example, Owner, or Contributor plus Role Based Access Control Administrator).
	A subscription administrator can perform the bootstrap on your behalf.
- A subscription approved for the Microsoft Discovery preview, with Discovery
	Platform Admin, Managed Identity Contributor, Network Contributor, and Storage
	Account Contributor permissions at the target resource group, as specified by
	the upstream sample. Creating the managed identity's role assignments also
	requires role-assignment write permissions at that scope.
- Available VM-family quota and Discovery/chat-model availability in the selected
	regions. Check GPU quota before selecting a GPU VM size.
- Complete the [Microsoft Discovery network security guide](https://learn.microsoft.com/en-us/azure/microsoft-discovery/how-to-configure-network-security),
	including the required NSP role assignments, before deploying with `azd`.

Register the prerequisite resource providers before provisioning, following the
[Discovery infrastructure quickstart](https://learn.microsoft.com/azure/microsoft-discovery/quickstart-infrastructure-portal).
The reference lists `Microsoft.AlertsManagement`, `Microsoft.App`,
`Microsoft.Authorization`, `Microsoft.Bing`, `Microsoft.CognitiveServices`,
`Microsoft.Compute`, `Microsoft.ContainerInstance`, `Microsoft.ContainerRegistry`,
`Microsoft.ContainerService`, `Microsoft.Discovery`, `Microsoft.DocumentDB`,
`Microsoft.Features`, `Microsoft.Insights`, `Microsoft.KeyVault`,
`Microsoft.MachineLearningServices`, `Microsoft.ManagedIdentity`, `Microsoft.Network`,
`Microsoft.OperationalInsights`, `Microsoft.ResourceGraph`, `Microsoft.Resources`,
`Microsoft.Search`, `Microsoft.Sql`, `Microsoft.Storage`, and `Microsoft.Web`.
Subscription-wide provider registrations are prerequisites, not resources owned
by this Terraform configuration, so destroying this project will not unregister them.

## Sign In And Select An Environment

Use the same user and tenant for Azure CLI and `azd`. This `azd` authentication
setting is global and affects other projects on this machine.

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

For another environment, use a different name instead of `dev`. Use 1-63
alphanumeric characters or hyphens, starting with an alphanumeric character.
For a different tenant, use `az login --tenant <tenant-id>`.

The Terraform region validation follows the reference template's allowed values:
`eastus`, `swedencentral`, and `uksouth`. Although its README also mentions East US 2,
its deployment parameter currently excludes that region. If an existing `azd`
environment uses another region, set `AZURE_LOCATION` to a supported value before
provisioning. Changing the location of already-managed resources can replace them;
review the preview before applying.

## Discovery Settings

Set the `global_tags` map in [infra/main.tfvars.json](infra/main.tfvars.json) to
apply tags to every taggable Terraform-managed project resource. It currently
supplies `CostControl=Ignore` and `SecurityControl=Ignore`; these values are not
hardcoded in the resource definitions. Direct Terraform callers can supply the
same map through their own tfvars. The variable defaults to an empty map.
Required project, environment, and Discovery service tags take precedence over
conflicting global tags. The separately bootstrapped state storage is not managed
by this map, and tags on Discovery-managed internal resources are controlled by
the service. Keep effective Discovery tags unchanged for existing deployments:
their tags are immutable, so changes can require resource recreation.

All settings below are optional `azd env set NAME VALUE` overrides. Resource names
use a deterministic suffix based on subscription and resource group, keeping names
within Discovery's limits and separating environments.

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

For example, after confirming regional GPU quota, select the reference's A100 SKU:

```bash
azd env set DISCOVERY_VM_SIZE Standard_NC24ads_A100_v4
azd env set DISCOVERY_MAX_NODES 1
```

Only if you need public preview workbench access and accept the network-isolation
tradeoff:

```bash
azd env set DISCOVERY_NETWORK_ISOLATION false
```

The data storage account deliberately retains the reference's network ACL default
of `Allow`: Discovery's control plane is not yet supported by the Storage
trusted-services bypass. Five subnet rules are preconfigured but do not restrict
access while this default is `Allow`. Blob access still requires Entra authorization;
anonymous and shared-key access are disabled. Do not switch the storage network
default to `Deny` without validating Discovery support.

Workspace, agent, and search subnets are delegated to `Microsoft.App/environments`.
The five workload subnets have Storage service endpoints. The private endpoint
subnet disables default outbound access and has no NAT gateway, matching upstream.

## Bootstrap State Storage

Run this once before the first provision. Choose a globally unique storage account
name containing 3-24 lowercase letters or digits. The dedicated state resource
group is deliberately outside Terraform's management so `azd down` cannot remove
the backend that holds its own state. Azure storage charges apply.

```bash
STATE_RESOURCE_GROUP="rg-gromacs-tfstate"
STATE_STORAGE_ACCOUNT="<globally-unique-storage-account-name>"
STATE_CONTAINER="tfstate"
USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

az group create --name "$STATE_RESOURCE_GROUP" --location "$LOCATION" \
	--tags CostControl=Ignore SecurityControl=Ignore

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
	--tags CostControl=Ignore SecurityControl=Ignore \
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

New role assignments can take several minutes to propagate. If container creation
returns `AuthorizationPermissionMismatch`, retry that command after propagation
before provisioning. Subscription Owner/Contributor alone does not grant Blob
data access. The role above is scoped to the dedicated state account; for an
existing container, an administrator can instead grant the role at container scope.

For existing state storage, skip creation, ensure your user has **Storage Blob Data
Contributor**, and set `RS_STORAGE_ACCOUNT` and `RS_CONTAINER_NAME` on each `azd`
environment. The storage account's firewall must allow your machine. This bootstrap
uses a public endpoint with authenticated access; it does not configure private
networking.

## Provision And Clean Up

Provisioning creates billable Discovery-managed services, storage, model capacity,
and compute. A zero minimum node count does not make the overall deployment free.
The Supercomputer and Workspace can each take 15-30 minutes; Terraform allows up
to 90 minutes per create/update/delete operation for them and the node pool.

```bash
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
azd provision --preview
azd provision
```

`azd` expands the environment variables in [infra/main.tfvars.json](infra/main.tfvars.json)
and [infra/provider.conf.json](infra/provider.conf.json), initializes the remote
backend, and runs Terraform. State locking uses Azure Blob leases. The blob name is
`microsoft-discovery-gromacs-sample/<subscription-id>/<environment-name>.tfstate`.
Teammates must configure the same environment name, subscription, and backend
settings, and have their own Blob data role assignment to share that state.

[infra/providers.tf](infra/providers.tf) explicitly enables `use_azuread_auth` and
`use_cli`. Remove any inherited `ARM_ACCESS_KEY`, `ARM_SAS_TOKEN`, or service
principal credential variables from your shell and `azd` environment so Terraform
uses your user login. Signing in with only `azd auth login` is not sufficient for
Terraform; the Azure CLI session must be active.

After provisioning, `azd` exports the `DISCOVERY_*_ID` Terraform outputs to the
environment. Open [Discovery Studio](https://studio.discovery.microsoft.com) to
find the workspace and project. Each user needs their own Discovery access roles;
the managed identity's assignments do not grant interactive users access.

To destroy only the Terraform-managed project resources:

```bash
azd down
```

The state account and its resource group remain. Delete them separately only when
no environments use them and any required state backups have been retained.
Do not change backend settings or environment names for existing infrastructure
without planning a Terraform state migration.

`azd down` destroys the Discovery deployment and its data storage, including stored
simulation outputs. Back up required data first. The separate Terraform state
storage bootstrap remains outside this deployment.

## Local Validation

These checks do not require Azure credentials or access to the remote state backend.
The tests use mocked providers and only build plans; they never deploy resources.

```bash
terraform -chdir=infra init -backend=false
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra test
```

Tests cover the quickstart defaults, six-subnet layout, delegations and endpoints,
storage authentication/CORS, identity and RBAC, API versions, optional cross-region
GPU configuration, `azd` string conversions, and invalid inputs. These tests do not
verify preview entitlement, NSP control-plane role assignments, Azure policies,
quota, model availability, or live service provisioning. Use `azd provision --preview` against your configured
subscription before applying; even a successful preview cannot guarantee capacity.

## Repository Files

- [azure.yaml](azure.yaml): selects Terraform as the `azd` infrastructure provider.
- [infra/](infra/): Terraform resources, inputs, outputs, and backend configuration.
- [infra/discovery.tf](infra/discovery.tf): the six Discovery resource types and their dependencies.
- [infra/network.tf](infra/network.tf), [infra/identity.tf](infra/identity.tf), and [infra/storage.tf](infra/storage.tf): foundation resources.
- [infra/tests/discovery.tftest.hcl](infra/tests/discovery.tftest.hcl): offline deployment configuration tests.
- [infra/.terraform.lock.hcl](infra/.terraform.lock.hcl): provider versions and checksums; keep this in version control.
- [.gitignore](.gitignore): excludes local `azd` settings, Terraform caches, state, and plans.

## References

- [Microsoft Discovery quickstarts](https://github.com/Azure/azure-quickstart-templates/tree/master/quickstarts/microsoft.discovery)
- [Pinned reference deployment](https://github.com/Azure/azure-quickstart-templates/blob/9a286202372ff9a9a4f4465e1ef30d7b0f3650c6/quickstarts/microsoft.discovery/discovery-infra-deployment/main.bicep)
- [Use Terraform with azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/use-terraform-for-azd)
- [Azure Blob backend and Entra authentication](https://developer.hashicorp.com/terraform/language/backend/azurerm)
