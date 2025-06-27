// Parameters
@description('Name prefix for the managed identity and related resources')
param name string

@description('Location for the managed identity')
param location string = resourceGroup().location

@description('Tags to be applied to the managed identity')
param tags object = {}

// Deploy managed identity with consistent naming
module managedIdentity '../identity/managedIdentity.bicep' = {
  scope: resourceGroup()
  name: 'managedIdentity-${name}'
  params: {
    name: '${name}-${uniqueString(resourceGroup().id)}-mi'
    location: location
    tags: tags
  }
}

// Key Vault role definitions for workload identity scenarios
// These roles provide the necessary permissions for applications to access Key Vault resources
var roleDefinitions = [
  {
    roleDefinitionId: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer - manage secrets
    description: 'Key Vault Secrets Officer'
  }
  {
    roleDefinitionId: 'a4417e6f-fecd-4de8-b567-7b0420556985' // Key Vault Certificates Officer - manage certificates  
    description: 'Key Vault Certificates Officer'
  }
  {
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User - read secrets
    description: 'Key Vault Secrets User'
  }
  {
    roleDefinitionId: 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba' // Key Vault Certificate User - read certificates
    description: 'Key Vault Certificate User'
  }
]

// Create role assignments for the managed identity
// These assignments will be scoped to the resource group level for security best practices
module roleAssignments '../identity/roleAssignment.bicep' = [
  for (roleDefinition, index) in roleDefinitions: {
    scope: resourceGroup()
    name: 'roleAssignment-${roleDefinition.description}-${index}'
    params: {
      principalId: managedIdentity.outputs.AZURE_MANAGED_IDENTITY_PRINCIPAL_ID
      roleDefinitionId: roleDefinition.roleDefinitionId
    }
  }
]

// Outputs for consuming modules
@description('Resource ID of the created managed identity')
output AZURE_MANAGED_IDENTITY_ID string = managedIdentity.outputs.AZURE_MANAGED_IDENTITY_ID

@description('Client ID of the managed identity')
output AZURE_MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.outputs.AZURE_MANAGED_IDENTITY_CLIENT_ID

@description('Principal ID of the managed identity')
output AZURE_MANAGED_IDENTITY_PRINCIPAL_ID string = managedIdentity.outputs.AZURE_MANAGED_IDENTITY_PRINCIPAL_ID

@description('Name of the managed identity')
output AZURE_MANAGED_IDENTITY_NAME string = managedIdentity.outputs.AZURE_MANAGED_IDENTITY_NAME

@description('Role assignment names for reference')
output AZURE_ROLE_ASSIGNMENT_NAMES array = [
  for (roleDefinition, index) in roleDefinitions: '${roleDefinition.description}-${index}'
]
