param name string
param location string

module keyVault '../security/keyVault.bicep' = {
  name: 'keyVault'
  scope: resourceGroup()
  params: {
    name: '${name}-${uniqueString(name,resourceGroup().id,subscription().id)}-kv'
    location: location
  }
}

module secret '../security/keyVaultSecret.bicep' = {
  name: 'keyVaultSecret'
  scope: resourceGroup()
  params: {
    name: name
    keyVaultName: keyVault.outputs.keyVaultName
  }
}
