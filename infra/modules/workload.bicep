param name string

param location string

@description('Log Analytics workspace resource ID for diagnostic logs')
param logAnalyticsWorkspaceId string
@description('SSH public key for accessing the AKS cluster')
@secure()
param sshPublicKey string

module aksCluster '../workload/aks.bicep' = {
  name: 'aksCluster'
  scope: resourceGroup()
  params: {
    name: '${name}-${uniqueString(name,resourceGroup().id,subscription().id)}-aks'
    location: location
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    sshPublicKey: sshPublicKey
  }
}

@description('The resource ID of the AKS cluster')
output AZURE_AKS_CLUSTER_ID string = aksCluster.outputs.AZURE_AKS_CLUSTER_ID

@description('The name of the AKS cluster')
output AZURE_AKS_CLUSTER_NAME string = aksCluster.outputs.AZURE_AKS_CLUSTER_NAME

module diagnosticSettings '../workload/diagnosticSettings.bicep' = {
  name: 'aksClusterDiagnostics'
  scope: resourceGroup()
  params: {
    aksClusterName: aksCluster.outputs.AZURE_AKS_CLUSTER_NAME
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}
