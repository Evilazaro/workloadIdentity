param principalId string
param roleDefinitionId string

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleDefinitionId)
  scope: tenant()
  properties: {
    principalId: principalId
    roleDefinitionId: principalId
    principalType: 'ServicePrincipal'
  }
}
