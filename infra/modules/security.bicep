param keyVaultName string
param secretName string
param location string

module keyVault '../security/keyVault.bicep' = {
  name: 'keyVault'
  scope: resourceGroup()
  params: {
    name: 'wkl-${uniqueString(keyVaultName,resourceGroup().id,subscription().id)}-kv'
    location: location
  }
}

output keyVaultId string = keyVault.outputs.keyVaultId
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri

module secret '../security/keyVaultSecret.bicep' = {
  name: 'keyVaultSecret'
  scope: resourceGroup()
  params: {
    name: secretName
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

output AZURE_KEYVAULT_SECRET_ID string = secret.outputs.AZURE_KEYVAULT_SECRET_ID
output AZURE_KEYVAULT_SECRET_NAME string = secret.outputs.AZURE_KEYVAULT_SECRET_NAME
