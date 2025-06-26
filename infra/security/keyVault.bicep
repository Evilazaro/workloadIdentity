param name string
param location string

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'premium'
      family: 'A'
    }
    enablePurgeProtection: true
    enableRbacAuthorization: true
    tenantId: tenant().tenantId
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
