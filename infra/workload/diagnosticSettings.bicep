@description('Name of the AKS cluster for which to configure diagnostic settings')
param aksClusterName string

@description('Resource ID of the Log Analytics workspace for storing diagnostic logs')
param logAnalyticsWorkspaceId string

// Reference existing AKS cluster with consistent API version
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' existing = {
  name: aksClusterName
  scope: resourceGroup()
}

// Configure comprehensive diagnostic settings for AKS cluster monitoring and compliance
resource aksClusterDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${aksCluster.name}-diagnostics'
  scope: aksCluster
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    // Enable critical Kubernetes control plane logs for security and troubleshooting
    logs: [
      {
        category: 'kube-apiserver' // API server logs for API call auditing
        enabled: true
      }
      {
        category: 'kube-audit' // Kubernetes audit logs for security monitoring
        enabled: true
      }
      {
        category: 'kube-controller-manager' // Controller manager logs for cluster state monitoring
        enabled: true
      }
      {
        category: 'kube-scheduler' // Scheduler logs for pod placement troubleshooting
        enabled: true
      }
      {
        category: 'cluster-autoscaler' // Autoscaler logs for scaling event monitoring
        enabled: true
      }
      {
        category: 'guard' // Azure AD Pod Identity logs for authentication monitoring
        enabled: true
      }
    ]
    // Enable all metrics for comprehensive cluster performance monitoring
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
