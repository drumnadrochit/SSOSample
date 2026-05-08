# SSO Sample Test Harness

This repository contains a front-end test harness for the Microsoft Entra Application Proxy KCD identity-mapping scenario described in the
[Microsoft Learn guide](https://learn.microsoft.com/en-us/entra/identity/app-proxy/how-to-configure-sso-with-kcd#working-with-different-on-premises-and-cloud-identities).

## Local app

Run the app locally with:

```bash
npm install
npm run dev
```

Build the static app with:

```bash
npm run build
```

## Container image

The repository includes a production Dockerfile for the front-end harness:

```bash
docker build -t kcd-test-harness:latest .
```

## Azure lab deployment

The infra files deploy a minimal-VM lab for this scenario:

- `infra/main.bicep`: deploys Azure Container Registry, Azure Container Apps, Log Analytics, and one Windows Server VM.
- `infra/scripts/bootstrap-kcd-lab.ps1`: optional helper script you can use for manual VM reconfiguration.
- `infra/main.bicepparam`: sample parameters file.

This architecture is intentionally optimized for the least number of VMs:

- The front-end test harness runs in Azure Container Apps from a Docker image.
- The identity-side lab runs on a single Windows VM that stages AD DS and the KCD/App Proxy prerequisites.

### Deploy to an Azure subscription (PowerShell)

Use this exact flow from the repo root.

1. Sign in and select your subscription.

```powershell
az login
az account set --subscription "<subscription-id-or-name>"
```

1. Define deployment variables.

```powershell
$RG = "rg-ssosample-lab"
$LOCATION = "eastus"
$PREFIX = "ssokcdlab"
$VM_ADMIN_USER = "azureadmin"
$VM_ADMIN_PASSWORD = "<strong-vm-admin-password>"
$DSRM_PASSWORD = "<strong-dsrm-password>"
$RDP_SOURCE = "<your-public-ip>/32"
```

1. Create the resource group.

```powershell
az group create --name $RG --location $LOCATION
```

1. Deploy the Bicep template.

```powershell
az deployment group create `
  --resource-group $RG `
  --name ssosample-deploy `
  --template-file infra/main.bicep `
  --parameters `
    namePrefix=$PREFIX `
    location=$LOCATION `
    adminUsername=$VM_ADMIN_USER `
    adminPassword=$VM_ADMIN_PASSWORD `
    safeModeAdministratorPassword=$DSRM_PASSWORD `
    allowedRdpSourceCidr=$RDP_SOURCE
```

1. Build and push the front-end image to the deployed Azure Container Registry.

```powershell
$LOGIN_SERVER = az deployment group show `
  --resource-group $RG `
  --name ssosample-deploy `
  --query "properties.outputs.acrLoginServer.value" -o tsv

$ACR_NAME = $LOGIN_SERVER.Split('.')[0]

az acr build --registry $ACR_NAME --image kcd-test-harness:latest .
```

1. Refresh the Container App to use the pushed image.

```powershell
az containerapp update `
  --resource-group $RG `
  --name "$PREFIX-app" `
  --image "$LOGIN_SERVER/kcd-test-harness:latest"
```

1. Get the deployment outputs.

```powershell
az deployment group show `
  --resource-group $RG `
  --name ssosample-deploy `
  --query "properties.outputs" -o json
```

1. Complete the identity-side setup on the Windows VM.

1. RDP to the VM using `labVmPublicIp` output.
1. Reboot once to complete AD DS staging.
1. Install and register the Microsoft Entra private network connector.
1. Publish the backend app with Application Proxy and configure KCD delegated identity.
1. Open `containerAppUrl` from the deployment outputs and run your test scenarios.

### Notes

- Restrict `allowedRdpSourceCidr` to your real public IP (`x.x.x.x/32`) instead of `*`.
- The default `infra/main.bicepparam` contains placeholder passwords; do not use it unchanged in real subscriptions.
- This deployment provides the lab shell with minimum VM count (one Windows VM + serverless container app hosting).

### Important limitation

The test harness app in this repo is a front-end simulator, not an Integrated Windows Authentication backend. The Azure deployment gives you the least-VM lab shell around that tester. If you want to validate true end-to-end KCD against the published application itself, replace the backend target with a Windows-auth-capable application and keep the same identity-side VM pattern.
