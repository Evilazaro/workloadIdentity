targetScope = 'subscription'

param solutionName string
param envName string
param location string
@secure()
param sshPublicKey string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: '${solutionName}-${envName}-${location}-rg'
  location: location
}

module identity 'modules/identity.bicep' = {
  scope: resourceGroup
  name: 'identity'
  params: {
    name: solutionName
  }
}

module security 'modules/security.bicep' = {
  scope: resourceGroup
  name: 'security'
  params: {
    keyVaultName: solutionName
    secretName: 'my-secret-demo'
    location: location
  }
}

output AZURE_KEYVAULT_ID string = security.outputs.keyVaultId
output AZURE_KEYVAULT_NAME string = security.outputs.keyVaultName
output AZURE_KEYVAULT_URI string = security.outputs.keyVaultUri
output AZURE_KEYVAULT_SECRET_ID string = security.outputs.AZURE_KEYVAULT_SECRET_ID
output AZURE_KEYVAULT_SECRET_NAME string = security.outputs.AZURE_KEYVAULT_SECRET_NAME

module logAnalytics 'monitoring/logAnalytics.bicep' = {
  scope: resourceGroup
  name: 'monitoring'
  params: {
    name: solutionName
    location: location
  }
}

module workload 'modules/workload.bicep' = {
  scope: resourceGroup
  name: 'workload'
  params: {
    name: solutionName
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
    sshPublicKey: sshPublicKey
  }
}
