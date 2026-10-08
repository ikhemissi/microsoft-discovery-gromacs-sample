# Microsoft Discovery GROMACS Sample

Infrastructure scaffold using Azure Developer CLI (`azd`) and Terraform. Currently
it provisions an environment-specific resource group; GROMACS compute resources
and application services are not configured yet.

Terraform state is stored in Azure Blob Storage and accessed using the signed-in
user's Microsoft Entra identity through Azure CLI. No storage account keys, SAS
tokens, or service principal secrets are required.

## Prerequisites

- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 and < 2.0.
- Bash for the commands below, run from the repository root.
- Permission to create resource groups and storage accounts in the subscription.
	The state-storage bootstrap also requires permission to assign Azure roles
	(for example, Owner, or Contributor plus Role Based Access Control Administrator).
	A subscription administrator can perform the bootstrap on your behalf.

## Sign In And Select An Environment

Use the same user and tenant for Azure CLI and `azd`. This `azd` authentication
setting is global and affects other projects on this machine.

```bash
azd config set auth.useAzCliAuth true
az login

SUBSCRIPTION_ID="<subscription-id>"
LOCATION="westeurope"
az account set --subscription "$SUBSCRIPTION_ID"

azd env new dev
azd env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION_ID"
azd env set AZURE_LOCATION "$LOCATION"
```

For another environment, use a different name instead of `dev`. Use 1-63
alphanumeric characters or hyphens, starting with an alphanumeric character.
For a different tenant, use `az login --tenant <tenant-id>`.

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

To destroy only the Terraform-managed project resources:

```bash
azd down
```

The state account and its resource group remain. Delete them separately only when
no environments use them and any required state backups have been retained.
Do not change backend settings or environment names for existing infrastructure
without planning a Terraform state migration.

## Repository Files

- [azure.yaml](azure.yaml): selects Terraform as the `azd` infrastructure provider.
- [infra/](infra/): Terraform resources, inputs, outputs, and backend configuration.
- [infra/.terraform.lock.hcl](infra/.terraform.lock.hcl): provider versions and checksums; keep this in version control.
- [.gitignore](.gitignore): excludes local `azd` settings, Terraform caches, state, and plans.

## References

- [Use Terraform with azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/use-terraform-for-azd)
- [Azure Blob backend and Entra authentication](https://developer.hashicorp.com/terraform/language/backend/azurerm)
