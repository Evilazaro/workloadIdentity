@description('Name of the managed identity')
param name string

@description('Location where the managed identity will be created')
param location string = resourceGroup().location

@description('Tags to be applied to the managed identity')
param tags object = {}

// Create user-assigned managed identity with latest stable API version
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

output AZURE_MANAGED_IDENTITY_ID string = managedIdentity.id
output AZURE_MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.properties.clientId
output AZURE_MANAGED_IDENTITY_PRINCIPAL_ID string = managedIdentity.properties.principalId
output AZURE_MANAGED_IDENTITY_NAME string = managedIdentity.name
