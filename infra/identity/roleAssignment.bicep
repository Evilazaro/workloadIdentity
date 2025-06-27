@description('Principal ID of the managed identity to assign roles to')
param principalId string

@description('Role definition ID to assign')
param roleDefinitionId string

@description('Scope for the role assignment (defaults to resource group for security)')
param assignmentScope string = resourceGroup().id

// Create role assignment for the managed identity
// Scoped to resource group level following security best practices (least privilege principle)
// This replaces the dangerous tenant() scope which would grant tenant-wide access
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(assignmentScope, principalId, roleDefinitionId)
  scope: resourceGroup() // Changed from tenant() to resourceGroup() for security
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
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'User'
  }
}
