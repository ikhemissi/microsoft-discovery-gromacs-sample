# Configuration

Optional overrides, set with `azd env set NAME VALUE` before `azd provision`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `DISCOVERY_DATA_PLANE_LOCATION` | `AZURE_LOCATION` | Region for networking, identity, storage and Discovery-managed resources |
| `DISCOVERY_VNET_ADDRESS_PREFIX` | `10.0.0.0/16` | IPv4 /16; six /24 subnets are allocated |
| `DISCOVERY_STORAGE_REPLICATION` | `GRS` | `LRS`, `ZRS`, `GRS`, `GZRS`, `RAGRS` or `RAGZRS` |
| `DISCOVERY_VM_SIZE` | `Standard_D4s_v6` | Simulation node pool VM size (CPU) |
| `DISCOVERY_MIN_NODES` / `DISCOVERY_MAX_NODES` | `0` / `3` | Simulation node pool size |
| `DISCOVERY_NODE_PRIORITY` | `Regular` | `Regular` or `Spot` |
| `DISCOVERY_INDEX_VM_SIZE` | `Standard_E20s_v6` | Indexing node pool VM size (memory-optimized) |
| `DISCOVERY_INDEX_MIN_NODES` / `DISCOVERY_INDEX_MAX_NODES` | `0` / `1` | Indexing node pool size |
| `DISCOVERY_CHAT_MODEL` / `DISCOVERY_CHAT_DEPLOYMENT` | `gpt-5.4` / `gpt-5-4` | Chat model and deployment name |
| `DISCOVERY_BOOKSHELF_PUBLIC_ACCESS` | `Enabled` | `Disabled` blocks Discovery Studio unless you add a private endpoint |
| `DISCOVERY_NETWORK_ISOLATION` | `true` | Workspace isolation tag |
| `DISCOVERY_ENABLE_GHCP_AI` / `DISCOVERY_ENABLE_EXTENSIONS` | `true` / `true` | Workbench feature tags (GitHub Copilot and AI features are in preview) |
| `DISCOVERY_ASSIGN_PROVISIONER_DATA_ROLES` | `false` | Grant your account Discovery and outputs-container data access (see below) |

Tags for all resources are set with `global_tags` in [infra/main.tfvars.json](../infra/main.tfvars.json).
Discovery tags are immutable, so changing them can recreate resources, and
changing the region of an existing environment can too; always check the preview.

## Permissions

Terraform grants the provisioning account **AcrPush** on the registry (to publish
the tool image) and **Storage Blob Data Contributor** on the papers and protocol
containers (to upload them). The Discovery identity pulls images and reads the
data through Terraform-managed grants. The extension never grants roles, scales
compute or runs simulations.

### Provisioner data roles

With `DISCOVERY_ASSIGN_PROVISIONER_DATA_ROLES=true`, Terraform also grants the
provisioning account **Microsoft Discovery Platform Contributor** on the resource
group and **Storage Blob Data Contributor** on the `discoveryoutputs` container,
for example to download simulation outputs. If these grants already exist,
import them into `azurerm_role_assignment.provisioner["discovery_platform_contributor"]`
and `azurerm_role_assignment.provisioner["storage_blob_data_contributor"]` first.
Setting the flag back to `false` removes them.
