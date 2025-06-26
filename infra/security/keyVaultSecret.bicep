param name string
param keyVaultName string


resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
  scope: resourceGroup()
}

resource kvSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  name: name
  parent: keyVault
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'Hello, World!' 
  }
}
