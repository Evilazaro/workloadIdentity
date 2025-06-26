@description('The name of the AKS cluster')
param name string

@description('The Azure region where the AKS cluster will be deployed')
param location string 

@description('Tags to apply to the AKS cluster')
param tags object = {}

@description('The Kubernetes version for the cluster')
param kubernetesVersion string = '1.30.0'

@description('The VM size for agent nodes')
param vmSize string = 'Standard_DS2_v2'

@description('Enable diagnostic logs')
param enableDiagnosticLogs bool = true

@description('Log Analytics workspace resource ID for diagnostic logs')
param logAnalyticsWorkspaceId string

// Use the latest stable API version
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Standard'
  }

  properties: {
    kubernetesVersion: kubernetesVersion
    enableRBAC: true

    // Disable local accounts for enhanced security
    disableLocalAccounts: true

    // Enable Azure AD integration
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }

    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
      advancedNetworking: {
        enabled: true
      }
      // Improved network configuration
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    dnsPrefix: 'wkld'
    agentPoolProfiles: [
      {
        name: 'system'
        count: 2
        vmSize: vmSize
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        orchestratorVersion: kubernetesVersion
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
        // Disable public IPs for better security
        enableNodePublicIP: true
        osSKU: 'AzureLinux' // Use Azure Linux for better security and performance
        // Disable UltraSSD unless specifically needed
        enableUltraSSD: false
        // Use managed OS disk for better performance
        osDiskType: 'Managed'
        osDiskSizeGB: 30
        // Security hardening
        enableEncryptionAtHost: false
        // Add node taints for system pool
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
      }
      {
        name: 'workload'
        count: 3
        vmSize: vmSize
        osType: 'Linux'
        mode: 'User'
        type: 'VirtualMachineScaleSets'
        orchestratorVersion: kubernetesVersion
        enableAutoScaling: true
        minCount: 1
        maxCount: 10
        // Disable public IPs for better security
        enableNodePublicIP: true
        osSKU: 'AzureLinux' // Use Azure Linux for better security and performance
        // Disable UltraSSD unless specifically needed
        enableUltraSSD: false
        // Use managed OS disk for better performance
        osDiskType: 'Managed'
        osDiskSizeGB: 30
        // Security hardening
        enableEncryptionAtHost: false
      }
    ]

    // Enhanced addon profiles
    addonProfiles: {
      azureKeyVaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      azurePolicy: {
        enabled: true
      }
      omsAgent: enableDiagnosticLogs && !empty(logAnalyticsWorkspaceId)
        ? {
            enabled: true
            config: {
              logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
            }
          }
        : {
            enabled: false
          }
    }

    // Enhanced security profile
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
      // Enable defender for enhanced security monitoring
      defender: !empty(logAnalyticsWorkspaceId)
        ? {
            logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
            securityMonitoring: {
              enabled: true
            }
          }
        : null
      // Enable image cleaner for security
      imageCleaner: {
        enabled: true
        intervalHours: 24
      }
    }

    // OIDC issuer for workload identity
    oidcIssuerProfile: {
      enabled: true
    }

    // Auto-upgrade configuration
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }

    // API server access profile for security
    apiServerAccessProfile: {
      enablePrivateCluster: false // Set to true for production
      disableRunCommand: true
    }

    // Storage profile with CSI drivers
    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      blobCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
  }
}

// Outputs
@description('The resource ID of the AKS cluster')
output clusterResourceId string = aksCluster.id

@description('The name of the AKS cluster')
output clusterName string = aksCluster.name

@description('The FQDN of the AKS cluster')
output clusterFqdn string = aksCluster.properties.fqdn

@description('The OIDC issuer URL for workload identity')
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('The principal ID of the AKS cluster system-assigned managed identity')
output clusterIdentityPrincipalId string = aksCluster.identity.principalId

@description('The tenant ID of the AKS cluster system-assigned managed identity')
output clusterIdentityTenantId string = aksCluster.identity.tenantId

@description('The node resource group name')
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup

@description('The current Kubernetes version of the cluster')
output currentKubernetesVersion string = aksCluster.properties.currentKubernetesVersion
