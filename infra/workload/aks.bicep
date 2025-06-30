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

@description('Enable SSH access to cluster nodes (required for SSH-only authentication)')
param enableSshAccess bool = true

@description('SSH public key data for node access. Required for SSH-only authentication. Must start with ssh-rsa, ssh-ed25519, or ecdsa-sha2-')
@secure()
param sshPublicKey string

@description('SSH username for node access')
param sshUsername string = 'azureuser'

@description('Enable private cluster for enhanced security (recommended for production)')
param enablePrivateCluster bool = false

@description('Authorized IP ranges for API server access (empty array allows all IPs)')
param authorizedIpRanges array = []

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

    // Enable local accounts for SSH-only authentication
    // Note: When using SSH-only auth, local accounts must be enabled
    disableLocalAccounts: false

    // Azure AD integration removed for SSH-only authentication
    // aadProfile is not configured to rely solely on SSH access

    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
      advancedNetworking: {
        enabled: true
      }
      // Improved network configuration
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
    dnsPrefix: 'wkld'

    // Linux profile for SSH access to nodes (required for SSH-only authentication)
    linuxProfile: enableSshAccess
      ? {
          adminUsername: sshUsername
          ssh: {
            publicKeys: [
              {
                keyData: sshPublicKey // SSH key is required for SSH-only authentication
              }
            ]
          }
        }
      : null

    agentPoolProfiles: [
      {
        name: 'system'
        count: 1
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        orchestratorVersion: kubernetesVersion
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
        // Disable public IPs for better security in production
        // Set to false for production environments to improve security
        enableNodePublicIP: false
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
        // Disable public IPs for better security in production
        // Set to false for production environments to improve security
        enableNodePublicIP: false
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

    // Enhanced security profile for SSH-only authentication
    securityProfile: {
      workloadIdentity: {
        enabled: true // Keep workload identity for secure service-to-service auth
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

    // API server access profile for enhanced security
    apiServerAccessProfile: {
      enablePrivateCluster: enablePrivateCluster
      authorizedIPRanges: !enablePrivateCluster && length(authorizedIpRanges) > 0 ? authorizedIpRanges : null
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
output AZURE_AKS_CLUSTER_ID string = aksCluster.id

@description('The name of the AKS cluster')
output AZURE_AKS_CLUSTER_NAME string = aksCluster.name

@description('The FQDN of the AKS cluster')
output AZURE_AKS_CLUSTER_FQDN string = aksCluster.properties.fqdn

@description('The OIDC issuer URL for workload identity')
output AZURE_OIDC_ISSUER_URL string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('The principal ID of the AKS cluster system-assigned managed identity')
output AZURE_AKS_CLUSTER_IDENTITY_PRINCIPAL_ID string = aksCluster.identity.principalId

@description('The tenant ID of the AKS cluster system-assigned managed identity')
output AZURE_AKS_CLUSTER_IDENTITY_TENANT_ID string = aksCluster.identity.tenantId

@description('The node resource group name')
output AZURE_NODE_RESOURCE_GROUP_NAME string = aksCluster.properties.nodeResourceGroup

@description('The current Kubernetes version of the cluster')
output AZURE_CURRENT_KUBERNETES_VERSION string = aksCluster.properties.currentKubernetesVersion

@description('SSH access configuration')
output sshConfiguration object = enableSshAccess
  ? {
      enabled: true
      username: sshUsername
      keyProvided: true // Always true when SSH access is enabled with SSH-only auth
      accessNote: 'SSH access is enabled. You can connect to nodes using: ssh ${sshUsername}@<node-ip>'
    }
  : {
      enabled: false
      note: 'SSH access is disabled for enhanced security'
    }
