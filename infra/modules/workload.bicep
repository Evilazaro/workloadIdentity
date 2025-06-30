// Parameters for AKS cluster deployment
@description('Base name for the AKS cluster and related resources')
param name string

@description('Location where the AKS cluster will be deployed')
param location string

@description('Tags to be applied to the AKS cluster and related resources')
param tags object = {}

@description('Log Analytics workspace resource ID for diagnostic logs')
param logAnalyticsWorkspaceId string

@description('SSH public key for accessing the AKS cluster nodes')
@secure()
param sshPublicKey string

module containerRegistry '../workload/containerRegistry.bicep' = {
  name: 'containerRegistry-${uniqueString(resourceGroup().id)}'
  scope: resourceGroup()
  params: {
    name: '${name}${uniqueString(resourceGroup().id)}acr' // Consistent naming with unique string
    location: location
  }
}

@description('The resource ID of the Azure Container Registry')
output AZURE_CONTAINER_REGISTRY_ID string = containerRegistry.outputs.AZURE_CONTAINER_REGISTRY_ID

@description('The name of the Azure Container Registry')
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.AZURE_CONTAINER_REGISTRY_NAME

output AZURE_CONTAINER_REGISTRY_LOGIN_SERVER string = containerRegistry.outputs.AZURE_CONTAINER_REGISTRY_LOGIN_SERVER

// Deploy AKS cluster with consistent naming and enhanced configuration
module aksCluster '../workload/aks.bicep' = {
  name: 'aksCluster-${uniqueString(resourceGroup().id)}'
  scope: resourceGroup()
  params: {
    name: '${name}-${uniqueString(resourceGroup().id)}-aks' // Simplified unique string generation for consistency
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    sshPublicKey: sshPublicKey
    // ACR integration parameters
    containerRegistryId: containerRegistry.outputs.AZURE_CONTAINER_REGISTRY_ID
    enableAcrIntegration: true
  }
}

// AKS cluster outputs using AZD naming conventions for consistency
@description('The resource ID of the AKS cluster')
output AZURE_AKS_CLUSTER_ID string = aksCluster.outputs.AZURE_AKS_CLUSTER_ID

@description('The name of the AKS cluster')
output AZURE_AKS_CLUSTER_NAME string = aksCluster.outputs.AZURE_AKS_CLUSTER_NAME

@description('The FQDN of the AKS cluster')
output AZURE_AKS_CLUSTER_FQDN string = aksCluster.outputs.AZURE_AKS_CLUSTER_FQDN

@description('The OIDC issuer URL for workload identity integration')
output AZURE_OIDC_ISSUER_URL string = aksCluster.outputs.AZURE_OIDC_ISSUER_URL

@description('The principal ID of the AKS cluster system-assigned managed identity')
output AZURE_AKS_CLUSTER_IDENTITY_PRINCIPAL_ID string = aksCluster.outputs.AZURE_AKS_CLUSTER_IDENTITY_PRINCIPAL_ID

@description('The node resource group name containing AKS worker nodes')
output AZURE_NODE_RESOURCE_GROUP_NAME string = aksCluster.outputs.AZURE_NODE_RESOURCE_GROUP_NAME

@description('ACR integration details')
output acrIntegration object = aksCluster.outputs.acrIntegration

// Deploy diagnostic settings for enhanced monitoring and compliance
// This module automatically depends on the AKS cluster due to output reference
module diagnosticSettings '../workload/diagnosticSettings.bicep' = {
  name: 'aksClusterDiagnostics-${uniqueString(resourceGroup().id)}'
  scope: resourceGroup()
  params: {
    aksClusterName: aksCluster.outputs.AZURE_AKS_CLUSTER_NAME
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}
