targetScope = 'subscription'

param solutionName string
param envName string
param location string

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

module security 'modules/security.bicep'= {
  scope: resourceGroup
  name: 'security'
  params: {
    name: solutionName
    location: location
  }
}

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
  }
}
