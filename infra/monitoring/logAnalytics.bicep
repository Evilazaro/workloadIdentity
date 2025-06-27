param name string
param location string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: '${name}-law'
  location: location
}

output logAnalyticsWorkspaceId string = logAnalytics.id
