@description('Name of the Key Vault')
param name string

@description('Location where the Key Vault will be created')
param location string

@description('Tags to be applied to the Key Vault')
param tags object = {}

// Create Key Vault with enhanced security configuration and latest stable API version
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'premium' // Using premium SKU for enhanced security features
      family: 'A'
    }
    enablePurgeProtection: true // Prevents accidental permanent deletion
    enableRbacAuthorization: true // Uses RBAC instead of access policies for better security
    enableSoftDelete: true // Enables soft delete for recovery capabilities
    softDeleteRetentionInDays: 90 // Maximum retention for soft-deleted items
    tenantId: tenant().tenantId
    // Enhanced security settings for production environments
    publicNetworkAccess: 'Enabled' // Can be restricted to 'Disabled' for private endpoint scenarios
    networkAcls: {
      defaultAction: 'Allow' // Can be set to 'Deny' with specific allow rules for enhanced security
      bypass: 'AzureServices'
    }
  }
}

output AZURE_KEYVAULT_ID string = keyVault.id
output AZURE_KEYVAULT_NAME string = keyVault.name
output AZURE_KEYVAULT_URI string = keyVault.properties.vaultUri
