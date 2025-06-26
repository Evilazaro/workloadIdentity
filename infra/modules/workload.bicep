param name string

param location string

@description('Log Analytics workspace resource ID for diagnostic logs')
param logAnalyticsWorkspaceId string
@description('SSH public key for accessing the AKS cluster')
@secure()
param sshPublicKey string

module aks '../workload/aks.bicep' = {
  name: 'aksCluster'
  scope: resourceGroup()
  params: {
    name: '${name}-${uniqueString(name,resourceGroup().id,subscription().id)}-aks'
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    sshPublicKey: sshPublicKey
  }
}

module diagnosticSettings '../workload/diagnosticSettings.bicep' = {
  name: 'aksClusterDiagnostics'
  scope: resourceGroup()
  params: {
    aksClusterName: aks.outputs.clusterName
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}
