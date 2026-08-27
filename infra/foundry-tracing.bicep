targetScope = 'resourceGroup'

@description('Name of the existing Microsoft Foundry account.')
@minLength(2)
param foundryAccountName string

@description('Name of the existing Microsoft Foundry project.')
@minLength(2)
param foundryProjectName string

@description('Name of the existing Application Insights resource.')
@minLength(1)
param appInsightsName string

var monitoringMetricsPublisherRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3913510d-42f4-4e42-8a64-420c390055eb'
)

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  name: foundryProjectName
  parent: foundry
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource telemetryPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(
    appInsights.id,
    foundryProject.id,
    monitoringMetricsPublisherRoleDefinitionId
  )
  scope: appInsights
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleDefinitionId
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  name: 'applicationinsights'
  parent: foundryProject
  properties: {
    authType: 'AAD'
    category: 'AppInsights'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsights.id
    }
    target: appInsights.id
    useWorkspaceManagedIdentity: true
  }
  dependsOn: [
    telemetryPublisher
  ]
}

output connectionName string = appInsightsConnection.name
output connectionResourceId string = appInsightsConnection.id
output telemetryPublisherRoleAssignmentId string = telemetryPublisher.id
