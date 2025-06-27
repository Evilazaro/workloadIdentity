param principalId string
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleDefinitionId)
  scope: tenant()
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}

resource roleAssignmentCurrentUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, deployer().objectId, roleDefinitionId)
  scope: tenant()
  properties: {
    principalId: deployer().objectId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'User'
  }
}
