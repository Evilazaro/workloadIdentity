param name string

module managedIdentity '../identity/managedIdentity.bicep' = {
  scope: resourceGroup()
  name: 'managedIdentity-${name}'
  params: {
    name: '${name}-${uniqueString(name,resourceGroup().id,subscription().id)}-mi'
  }
}

var roleDefinitions = [
  {
    roleDefinitionId: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  }
  {
    roleDefinitionId: 'a4417e6f-fecd-4de8-b567-7b0420556985'
  }
  {
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'
  }
  {
    roleDefinitionId: 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'
  }
]

module roleAssignments '../identity/roleAssignment.bicep' = [
  for roleDefinition in roleDefinitions: {
    scope: resourceGroup()
    name: 'roleAssignment-${roleDefinition.roleDefinitionId}'
    params: {
      principalId: managedIdentity.outputs.managedIdentityPrincipalId
      roleDefinitionId: roleDefinition.roleDefinitionId
    }
  }
]
