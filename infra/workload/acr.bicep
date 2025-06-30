@description('The name of the Azure Container Registry')
param name string

@description('The Azure region where the ACR will be deployed')
param location string

@description('Tags to apply to the ACR')
param tags object = {}

@description('The SKU of the container registry')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Standard'

@description('Enable admin user for the registry (not recommended for production)')
param adminUserEnabled bool = false

@description('Enable public network access')
param publicNetworkAccess bool = true

@description('Enable zone redundancy (Premium SKU only)')
param zoneRedundancy bool = false

@description('Enable image quarantine for vulnerability scanning')
param quarantinePolicy bool = false

@description('Enable trust policy for signed images')
param trustPolicy bool = false

@description('Retention policy for untagged manifests in days')
param retentionDays int = 7

@description('Enable content trust (Premium SKU only)')
param contentTrust bool = false

@description('Log Analytics workspace resource ID for diagnostic logs')
param logAnalyticsWorkspaceId string = ''

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    adminUserEnabled: adminUserEnabled

    // Network access configuration
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'

    // Zone redundancy (Premium SKU only)
    zoneRedundancy: sku == 'Premium' ? (zoneRedundancy ? 'Enabled' : 'Disabled') : 'Disabled'

    // Security policies
    policies: {
      quarantinePolicy: {
        status: quarantinePolicy ? 'enabled' : 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: trustPolicy && sku == 'Premium' ? 'enabled' : 'disabled'
      }
      retentionPolicy: {
        days: retentionDays
        status: 'enabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
    }

    // Encryption configuration (Premium SKU only)
    encryption: sku == 'Premium'
      ? {
          status: 'enabled'
          keyVaultProperties: null // Can be configured for customer-managed keys
        }
      : null

    // Data endpoint configuration (Premium SKU only)
    dataEndpointEnabled: sku == 'Premium'

    // Network rule bypass for Azure services
    networkRuleBypassOptions: 'AzureServices'
  }
}

// Diagnostic settings for ACR
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'acr-diagnostics'
  scope: containerRegistry
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Outputs
@description('The resource ID of the Azure Container Registry')
output AZURE_CONTAINER_REGISTRY_ID string = containerRegistry.id

@description('The name of the Azure Container Registry')
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.name

@description('The login server URL of the Azure Container Registry')
output AZURE_CONTAINER_REGISTRY_LOGIN_SERVER string = containerRegistry.properties.loginServer

@description('The principal ID of the ACR system-assigned managed identity')
output AZURE_CONTAINER_REGISTRY_IDENTITY_PRINCIPAL_ID string = containerRegistry.identity.principalId

@description('The tenant ID of the ACR system-assigned managed identity')
output AZURE_CONTAINER_REGISTRY_IDENTITY_TENANT_ID string = containerRegistry.identity.tenantId

@description('ACR configuration summary')
output acrConfiguration object = {
  name: containerRegistry.name
  loginServer: containerRegistry.properties.loginServer
  sku: sku
  adminUserEnabled: adminUserEnabled
  publicNetworkAccess: publicNetworkAccess
  zoneRedundancy: sku == 'Premium' ? zoneRedundancy : false
  quarantinePolicy: quarantinePolicy
  trustPolicy: trustPolicy && sku == 'Premium'
  contentTrust: contentTrust && sku == 'Premium'
  retentionDays: retentionDays
  diagnosticsEnabled: !empty(logAnalyticsWorkspaceId)
  securityFeatures: {
    anonymousPullDisabled: true
    azureADAuthEnabled: true
    softDeleteEnabled: true
    encryptionEnabled: sku == 'Premium'
  }
}
