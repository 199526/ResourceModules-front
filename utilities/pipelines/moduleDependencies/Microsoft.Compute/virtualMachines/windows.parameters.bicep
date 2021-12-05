targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

// Resource Group
@description('Required. The name of the resource group to deploy for a testing purposes')
param resourceGroupName string

// Shared
var location = deployment().location
var serviceShort = 'vmwinpar'

var managedIdentityParameters = {
  name: 'adp-sxx-msi-${serviceShort}-01'
}

resource miRef 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  scope: az.resourceGroup(resourceGroupName)
  name: managedIdentityParameters.name
}

var storageAccountParameters = {
  name: 'adpsxxazsa${serviceShort}01'
  storageAccountKind: 'StorageV2'
  storageAccountSku: 'Standard_LRS'
  allowBlobPublicAccess: false
  blobServices: {
    containers: [
      {
        name: 'scripts'
        publicAccess: 'None'
      }
    ]
  }
  roleAssignments: [
    {
      roleDefinitionIdOrName: 'Owner'
      principalIds: [
        miRef.properties.principalId
      ]
    }
  ]
}

var storageAccountDeploymentScriptParameters = {
  name: 'sxx-ds-sa-${serviceShort}-01'
  userAssignedIdentities: {
    '${miRef.properties.principalId}': {}
  }
  cleanupPreference: 'OnSuccess'
  arguments: ' -StorageAccountName ${storageAccountParameters.name} -ResourceGroupName ${resourceGroupName} -ContainerName "scripts" -FileName "scriptExtensionMasterInstaller.ps1"'
  scriptContent: '''
      param(
        [string] $StorageAccountName,
        [string] $ResourceGroupName,
        [string] $ContainerName,
        [string] $FileName
      )
      Write-Verbose "Create file [$FileName]" -Verbose
      $file = New-Item -Value "Write-Host 'I am content'" -Path $FileName -Force

      Write-Verbose "Getting storage account [$StorageAccountName|$ResourceGroupName] context." -Verbose
      $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ErrorAction 'Stop'

      Write-Verbose 'Uploading file [$fileName]' -Verbose
      Set-AzStorageBlobContent -File $file.FullName -Container $ContainerName -Context $storageAccount.Context -Force -ErrorAction 'Stop' | Out-Null
    '''
}

var logAnalyticsWorkspaceParameters = {
  name: 'adp-sxx-law-${serviceShort}-01'
}

var eventHubParameters = {
  name: 'adp-sxx-evhns-${serviceShort}-01'
  eventHubs: [
    {
      name: 'adp-sxx-evh-${serviceShort}-01'
      authorizationRules: [
        {
          name: 'RootManageSharedAccessKey'
          rights: [
            'Listen'
            'Manage'
            'Send'
          ]
        }
      ]
    }
  ]
}

var networkSecurityGroupParameters = {
  name: 'adp-sxx-nsg-${serviceShort}-01'
}

var virtualNetworkInputParameters = {
  name: 'adp-sxx-vnet-${serviceShort}-01'
  addressPrefixes: [
    '10.0.0.0/16'
  ]
  subnets: [
    {
      name: 'sxx-subnet-x-01'
      addressPrefix: '10.0.0.0/24'
      networkSecurityGroupName: networkSecurityGroupParameters.name
    }
  ]
}

var keyVaultParameters = {
  name: 'adp-sxx-kv-${serviceShort}-01'
  enablePurgeProtection: false
  accessPolicies: [
    {
      objectId: managedIdentity.outputs.msiPrincipalId
      permissions: {
        secrets: [
          'All'
        ]
      }
    }
  ]
}

var keyVaultDeploymentScriptParameters = {
  name: 'sxx-ds-kv-${serviceShort}-01'
  userAssignedIdentities: {
    '${managedIdentity.outputs.msiResourceId}': {}
  }
  cleanupPreference: 'OnSuccess'
  arguments: ' -keyVaultName ${keyVaultParameters.name}'
  scriptContent: '''
      param(
        [string] $keyVaultName
      )

      $usernameString = (-join ((65..90) + (97..122) | Get-Random -Count 9 -SetSeed 1 | % {[char]$_ + "$_"})).substring(0,19) # max length
      $passwordString = (New-Guid).Guid.SubString(0,19)

      $userName = ConvertTo-SecureString -String $usernameString -AsPlainText -Force
      $password = ConvertTo-SecureString -String $passwordString -AsPlainText -Force

      # VirtualMachines and VMSS
      Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'adminUsername' -SecretValue $username
      Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'adminPassword' -SecretValue $password
    '''
}

var recoveryServicesVaultParameters = {
  name: 'adp-sxx-rsv-${serviceShort}-01'
  backupPolicies: [
    {
      name: 'VMpolicy'
      type: 'Microsoft.RecoveryServices/vaults/backupPolicies'
      properties: {
        backupManagementType: 'AzureIaasVM'
        schedulePolicy: {
          schedulePolicyType: 'SimpleSchedulePolicy'
          scheduleRunFrequency: 'Daily'
          scheduleRunTimes: [
            '2019-11-07T07:0:0Z'
          ]
          scheduleWeeklyFrequency: 0
        }
        retentionPolicy: {
          retentionPolicyType: 'LongTermRetentionPolicy'
          dailySchedule: {
            retentionTimes: [
              '2019-11-07T04:30:0Z'
            ]
            retentionDuration: {
              count: 30
              durationType: 'Days'
            }
          }
        }
      }
    }
  ]
}

// =========== //
// Deployments //
// =========== //

module resourceGroup '../../../../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${uniqueString(deployment().name, location)}-rg'
  params: {
    name: resourceGroupName
    location: location
  }
}

module managedIdentity '../../../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-mi'
  params: {
    name: managedIdentityParameters.name
  }
  dependsOn: [
    resourceGroup
  ]
}

module storageAccount '../../../../../arm/Microsoft.Storage/storageAccounts/deploy.bicep' = {
  name: '${uniqueString(deployment().name, location)}-sa'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: storageAccountParameters.name
    storageAccountKind: storageAccountParameters.storageAccountKind
    storageAccountSku: storageAccountParameters.storageAccountSku
    allowBlobPublicAccess: storageAccountParameters.allowBlobPublicAccess
    blobServices: storageAccountParameters.blobServices
    roleAssignments: storageAccountParameters.roleAssignments
  }
  dependsOn: [
    resourceGroup
  ]
}

module storageAccountDeploymentScript '../../../../../arm/Microsoft.Resources/deploymentScripts/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-sa-ds'
  params: {
    name: storageAccountDeploymentScriptParameters.name
    arguments: storageAccountDeploymentScriptParameters.arguments
    userAssignedIdentities: storageAccountDeploymentScriptParameters.userAssignedIdentities
    scriptContent: storageAccountDeploymentScriptParameters.scriptContent
    cleanupPreference: storageAccountDeploymentScriptParameters.cleanupPreference
  }
  dependsOn: [
    resourceGroup
    storageAccount
    managedIdentity
  ]
}

module logAnalyticsWorkspace '../../../../../arm/Microsoft.OperationalInsights/workspaces/deploy.bicep' = {
  name: '${uniqueString(deployment().name, location)}-oms'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceParameters.name
  }
  dependsOn: [
    resourceGroup
  ]
}

module eventHubNamespace '../../../../../arm/Microsoft.EventHub/namespaces/deploy.bicep' = {
  name: '${uniqueString(deployment().name, location)}-ehn'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: eventHubParameters.name
    eventHubs: eventHubParameters.eventHubs
  }
  dependsOn: [
    resourceGroup
  ]
}

module networkSecurityGroup '../../../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-nsg'
  params: {
    name: networkSecurityGroupParameters.name
  }
  dependsOn: [
    resourceGroup
  ]
}

module virtualNetwork '../../../../../arm/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-vnet'
  params: {
    name: virtualNetworkInputParameters.name
    addressPrefixes: virtualNetworkInputParameters.addressPrefixes
    subnets: virtualNetworkInputParameters.subnets
  }
  dependsOn: [
    resourceGroup
    networkSecurityGroup
  ]
}

module recoveryServicesVault '../../../../../arm/Microsoft.RecoveryServices/vaults/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-rsv'
  params: {
    name: recoveryServicesVaultParameters.name
    backupPolicies: recoveryServicesVaultParameters.backupPolicies
  }
  dependsOn: [
    resourceGroup
  ]
}

module keyVault '../../../../../arm/Microsoft.KeyVault/vaults/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-kv'
  params: {
    name: keyVaultParameters.name
    enablePurgeProtection: keyVaultParameters.enablePurgeProtection
    accessPolicies: keyVaultParameters.accessPolicies
  }
  dependsOn: [
    resourceGroup
  ]
}

module keyVaultdeploymentScript '../../../../../arm/Microsoft.Resources/deploymentScripts/deploy.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-kv-ds'
  params: {
    name: keyVaultDeploymentScriptParameters.name
    arguments: keyVaultDeploymentScriptParameters.arguments
    userAssignedIdentities: keyVaultDeploymentScriptParameters.userAssignedIdentities
    scriptContent: keyVaultDeploymentScriptParameters.scriptContent
    cleanupPreference: keyVaultDeploymentScriptParameters.cleanupPreference
  }
  dependsOn: [
    resourceGroup
    keyVault
    managedIdentity
  ]
}

@description('The name of the resource group')
output resourceGroupName string = resourceGroup.outputs.resourceGroupName

@description('The resource ID of the resource group')
output resourceGroupResourceId string = resourceGroup.outputs.resourceGroupResourceId
