targetScope = 'resourceGroup'

@description('Deployment location.')
param location string = resourceGroup().location

@description('Short prefix used for Azure resource names.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'ssokcdlab'

@description('Windows administrator username for the lab VM.')
param adminUsername string = 'azureadmin'

@secure()
@description('Windows administrator password for the lab VM.')
param adminPassword string

@secure()
@description('Safe mode password for the Active Directory forest deployed on the lab VM.')
param safeModeAdministratorPassword string

@description('CIDR allowed to RDP to the Windows lab VM.')
param allowedRdpSourceCidr string = '*'

@description('AD DS forest name to create on the lab VM.')
param domainName string = 'corp.contoso.local'

@description('NetBIOS name for the AD DS forest.')
param netbiosName string = 'CORP'

@description('Windows VM size for the identity-side lab host.')
param vmSize string = 'Standard_D4s_v5'

@description('Container image repository name to build and push into ACR.')
param containerImageRepository string = 'kcd-test-harness'

@description('Container image tag to deploy into Azure Container Apps.')
param containerImageTag string = 'latest'

@description('Container Apps CPU allocation.')
param containerCpu int = 1

@description('Container Apps memory allocation.')
param containerMemory string = '2Gi'

@description('Address prefix for the single lab virtual network.')
param virtualNetworkAddressPrefix string = '10.42.0.0/16'

@description('Subnet prefix for the Windows lab VM.')
param vmSubnetPrefix string = '10.42.1.0/24'

@description('Tags applied to all resources.')
param tags object = {
  environment: 'lab'
  workload: 'entra-kcd-test-harness'
}

var trimmedPrefix = toLower(replace(namePrefix, '-', ''))
var acrBase = empty(trimmedPrefix) ? 'ssokcdlab' : trimmedPrefix
var acrName = take('${acrBase}acr000', 50)
var containerAppName = '${namePrefix}-app'
var containerEnvName = '${namePrefix}-cae'
var logAnalyticsName = '${namePrefix}-law'
var virtualNetworkName = '${namePrefix}-vnet'
var vmSubnetName = 'vm-subnet'
var nsgName = '${namePrefix}-nsg'
var publicIpName = '${namePrefix}-pip'
var nicName = '${namePrefix}-nic'
var vmName = '${namePrefix}-vm'
var extensionName = 'bootstrapKcdLab'
var containerImage = '${acr.properties.loginServer}/${containerImageRepository}:${containerImageTag}'
var publishedHarnessUrl = 'https://${containerApp.properties.configuration.ingress.fqdn}'
var bootstrapCommand = 'powershell -ExecutionPolicy Bypass -Command "Install-WindowsFeature -Name AD-Domain-Services,RSAT-AD-PowerShell,Web-Server,Web-Windows-Auth -IncludeManagementTools; Install-ADDSForest -DomainName \'${domainName}\' -DomainNetbiosName \'${netbiosName}\' -InstallDns -NoRebootOnCompletion -SafeModeAdministratorPassword (ConvertTo-SecureString \'${safeModeAdministratorPassword}\' -AsPlainText -Force) -Force; New-Item -Path C:\\Lab -ItemType Directory -Force | Out-Null; Set-Content -Path C:\\Lab\\NextSteps.txt -Value \'Open ${publishedHarnessUrl} after VM reboot and connector setup.\'"'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
        type: 'Notary'
      }
    }
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'
        }
      ]
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'test-harness'
          image: containerImage
          resources: {
            cpu: containerCpu
            memory: containerMemory
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, containerApp.name, 'AcrPull')
  scope: acr
  properties: {
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-rdp'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: allowedRdpSourceCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
          description: 'Restrict RDP access to the declared source CIDR.'
        }
      }
      {
        name: 'allow-http-from-vnet'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 110
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '80'
            '443'
            '8080'
          ]
          description: 'Allow on-box service testing from the lab network.'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig01'
        properties: {
          subnet: {
            id: '${virtualNetwork.id}/subnets/${vmSubnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource bootstrapExtension 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = {
  name: extensionName
  parent: vm
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    protectedSettings: {
      commandToExecute: bootstrapCommand
    }
  }
}

output acrLoginServer string = acr.properties.loginServer
output builtContainerImage string = containerImage
output containerAppUrl string = publishedHarnessUrl
output labVmPublicIp string = publicIp.properties.ipAddress
output manualNextSteps array = [
  'Build and push the app image before deploying or immediately after: az acr build --registry ${acr.name} --image ${containerImageRepository}:${containerImageTag} .'
  'RDP to the lab VM after deployment and reboot it once so the new AD DS forest finishes initialization.'
  'Install and register the Microsoft Entra private network connector on the Windows VM, then publish the backend app through Application Proxy.'
  'Use the deployed Container App URL as the public test harness, or replace the backend target with a Windows-auth-capable app if you want to validate real KCD rather than only the tester UI.'
]
