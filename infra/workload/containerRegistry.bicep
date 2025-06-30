param name string
param location string

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: true
    anonymousPullEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.name
output AZURE_CONTAINER_REGISTRY_LOGIN_SERVER string = containerRegistry.properties.loginServer
output AZURE_CONTAINER_REGISTRY_ID string = containerRegistry.id
