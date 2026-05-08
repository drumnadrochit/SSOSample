# SSO Sample Test Harness

This repository contains a front-end test harness for the Microsoft Entra Application Proxy KCD identity-mapping scenario described here:

- https://learn.microsoft.com/en-us/entra/identity/app-proxy/how-to-configure-sso-with-kcd#working-with-different-on-premises-and-cloud-identities

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

The `infra` folder contains a minimal-VM Azure lab deployment for this scenario:

- `infra/main.bicep`: deploys Azure Container Registry, Azure Container Apps, Log Analytics, and one Windows Server VM.
- `infra/scripts/bootstrap-kcd-lab.ps1`: prepares the Windows VM for AD DS and connector-side lab work.
- `infra/main.bicepparam`: sample parameters file.

This architecture is intentionally optimized for the least number of VMs:

- The front-end test harness runs in Azure Container Apps from a Docker image.
- The identity-side lab runs on a single Windows VM that stages AD DS and the KCD/App Proxy prerequisites.

### Deploy sequence

1. Build and push the test harness image to the Azure Container Registry created by the template.
2. Deploy the Bicep template.
3. RDP to the Windows VM and reboot it once so the staged AD DS forest initialization completes.
4. Install and register the Microsoft Entra private network connector on that VM.
5. Publish the backend application in Application Proxy and configure KCD plus delegated login identity.

Example deployment flow:

```bash
az deployment group create --resource-group <rg> --template-file infra/main.bicep --parameters infra/main.bicepparam
az acr build --registry <acr-name> --image kcd-test-harness:latest .
```

### Important limitation

The test harness app in this repo is a front-end simulator, not an Integrated Windows Authentication backend. The Azure deployment gives you the least-VM lab shell around that tester. If you want to validate true end-to-end KCD against the published application itself, replace the backend target with a Windows-auth-capable application and keep the same identity-side VM pattern.
