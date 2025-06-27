@description('Name of the secret')
param name string

@description('Name of the Key Vault where the secret will be stored')
param keyVaultName string

@description('Value of the secret to be stored')
@secure()
param secretValue string

// Reference existing Key Vault with latest stable API version
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup()
}

// Create secret in Key Vault with parameterized value
resource kvSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: name
  parent: keyVault
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: secretValue // Use parameterized value instead of hard-coded string
  }
}

output AZURE_KEYVAULT_SECRET_ID string = kvSecret.id
output AZURE_KEYVAULT_SECRET_NAME string = kvSecret.name
