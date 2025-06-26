targetScope = 'subscription'

param solutionName string
param envName string
param location string

var componentsName string = '${solutionName}-${envName}-${location}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: '${componentsName}-rg'
  location: location
}

module identity 'modules/identity.bicep' = {
  scope: resourceGroup
  name: 'identity'
  params: {
    name: solutionName
  }
}

module logAnalytics 'monitoring/logAnalytics.bicep' = {
  scope: resourceGroup
  name: 'monitoring'
  params: {
    name: componentsName
    location: location
  }
}

module aks 'aks/aks.bicep' = {
  scope: resourceGroup
  name: 'aksCluster'
  params: {
    name: solutionName
    logAnalyticsWorkspaceId: logAnalytics.outputs.logAnalyticsWorkspaceId
  }
}
