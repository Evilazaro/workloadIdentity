// Parameters for Key Vault and secret configuration
@description('Name of the secret to be created in Key Vault')
param secretName string

@description('Location where the Key Vault will be deployed')
param location string

@description('Tags to be applied to the Key Vault resources')
param tags object = {}

@description('Value for the secret (should be passed securely from deployment pipeline)')
@secure()
param secretValue string

// Deploy Key Vault with consistent naming and enhanced security
module keyVault '../security/keyVault.bicep' = {
  name: 'keyVault-${uniqueString(resourceGroup().id)}'
  scope: resourceGroup()
  params: {
    name: 'wkl-${uniqueString(resourceGroup().id)}-kv' // Simplified unique string generation for consistency
    location: location
    tags: tags
  }
}

// Key Vault outputs using AZD naming conventions for consistency
output AZURE_KEYVAULT_ID string = keyVault.outputs.AZURE_KEYVAULT_ID
output AZURE_KEYVAULT_NAME string = keyVault.outputs.AZURE_KEYVAULT_NAME
output AZURE_KEYVAULT_URI string = keyVault.outputs.AZURE_KEYVAULT_URI

// Deploy secret to Key Vault with parameterized value
module secret '../security/keyVaultSecret.bicep' = {
  name: 'keyVaultSecret-${uniqueString(resourceGroup().id)}'
  scope: resourceGroup()
  params: {
    name: secretName
    keyVaultName: keyVault.outputs.AZURE_KEYVAULT_NAME
    secretValue: secretValue // Pass the secure parameter instead of hard-coded value
  }
}

output AZURE_KEYVAULT_SECRET_ID string = secret.outputs.AZURE_KEYVAULT_SECRET_ID
output AZURE_KEYVAULT_SECRET_NAME string = secret.outputs.AZURE_KEYVAULT_SECRET_NAME
