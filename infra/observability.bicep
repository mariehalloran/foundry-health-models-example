targetScope = 'resourceGroup'

param environmentName string
param location string
param logAnalyticsWorkspaceName string
param managedIdentityName string
param alertEmailAddress string

var resourceToken = toLower(
  uniqueString(subscription().id, resourceGroup().id, location, environmentName)
)
var commonTags = {
  'azd-env-name': environmentName
  application: 'clinical-trial-chat'
  component: 'observability'
}
var monitoringMetricsPublisherRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3913510d-42f4-4e42-8a64-420c390055eb'
)

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'azins${resourceToken}'
  location: location
  kind: 'web'
  tags: commonTags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    DisableLocalAuth: true
    DisableIpMasking: false
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource telemetryPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(
    appInsights.id,
    managedIdentity.id,
    monitoringMetricsPublisherRoleDefinitionId
  )
  scope: appInsights
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleDefinitionId
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource healthActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'azag${resourceToken}'
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: 'ctchealth'
    enabled: true
    emailReceivers: [
      {
        name: 'health-alert-recipient'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsName string = appInsights.name
output appInsightsResourceId string = appInsights.id
output actionGroupName string = healthActionGroup.name
output actionGroupResourceId string = healthActionGroup.id
output telemetryPublisherRoleAssignmentId string = telemetryPublisher.id
