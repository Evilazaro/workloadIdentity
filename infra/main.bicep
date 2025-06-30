targetScope = 'subscription'

param solutionName string
param envName string
param location string
@secure()
param sshPublicKey string

var resourceGroupName = '${solutionName}-${envName}-${location}-rg'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
}

output AZURE_RESOURCE_GROUP_NAME string = resourceGroup.name
output AZURE_RESOURCE_GROUP_ID string = resourceGroup.id

module identity 'modules/identity.bicep' = {
  scope: resourceGroup
  name: 'identity'
  params: {
    name: solutionName
  }
}

output AZURE_MANAGED_IDENTITY_ID string = identity.outputs.AZURE_MANAGED_IDENTITY_ID
output AZURE_MANAGED_IDENTITY_CLIENT_ID string = identity.outputs.AZURE_MANAGED_IDENTITY_CLIENT_ID
output AZURE_MANAGED_IDENTITY_PRINCIPAL_ID string = identity.outputs.AZURE_MANAGED_IDENTITY_PRINCIPAL_ID
output AZURE_MANAGED_IDENTITY_NAME string = identity.outputs.AZURE_MANAGED_IDENTITY_NAME

module security 'modules/security.bicep' = {
  scope: resourceGroup
  name: 'security'
  params: {
    secretName: 'my-secret-demo'
    secretValue: 'Hello, World!' // This should be passed securely in production
    location: location
  }
}

output AZURE_KEYVAULT_ID string = security.outputs.AZURE_KEYVAULT_ID
output AZURE_KEYVAULT_NAME string = security.outputs.AZURE_KEYVAULT_NAME
output AZURE_KEYVAULT_URI string = security.outputs.AZURE_KEYVAULT_URI
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
@description('The resource ID of the AKS cluster')
output AZURE_AKS_CLUSTER_ID string = workload.outputs.AZURE_AKS_CLUSTER_ID

@description('The name of the AKS cluster')
output AZURE_AKS_CLUSTER_NAME string = workload.outputs.AZURE_AKS_CLUSTER_NAME

output AZURE_AKS_CLUSTER_FQDN string = workload.outputs.AZURE_AKS_CLUSTER_FQDN

@description('The OIDC issuer URL for workload identity')
output AZURE_OIDC_ISSUER_URL string = workload.outputs.AZURE_OIDC_ISSUER_URL
