targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Resource group containing the health model. Defaults to the monitored resource group.')
param healthModelResourceGroupName string = resourceGroup().name

@description('Optional Log Analytics workspace name. Set it to enable KQL signal access.')
param logAnalyticsWorkspaceName string = ''

var monitoringReaderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
)
var logAnalyticsReaderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '73c42c96-874c-492b-b04d-ab87d138a893'
)
var logAnalyticsDataReaderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3b03c2da-16b3-4a49-8834-0f8130efdd3b'
)

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' existing = {
  name: healthModelName
  scope: resourceGroup(healthModelResourceGroupName)
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = if (!empty(logAnalyticsWorkspaceName)) {
  name: logAnalyticsWorkspaceName
}

// Platform metrics are collected automatically. The health model identity needs
// read access to the monitored resources; diagnostic settings are not required.
resource healthModelMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, healthModel.id, monitoringReaderRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    principalId: healthModel.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: monitoringReaderRoleDefinitionId
  }
}

resource healthModelLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(logAnalyticsWorkspaceName)) {
  name: guid(logAnalytics.id, healthModel.id, logAnalyticsReaderRoleDefinitionId)
  scope: logAnalytics
  properties: {
    principalId: healthModel.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: logAnalyticsReaderRoleDefinitionId
  }
}

resource healthModelLogAnalyticsDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(logAnalyticsWorkspaceName)) {
  name: guid(logAnalytics.id, healthModel.id, logAnalyticsDataReaderRoleDefinitionId)
  scope: logAnalytics
  properties: {
    principalId: healthModel.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: logAnalyticsDataReaderRoleDefinitionId
  }
}

output healthModelResourceId string = healthModel.id
output metricsScope string = resourceGroup().id
output monitoringReaderRoleAssignmentId string = healthModelMonitoringReader.id
output logAnalyticsReaderRoleAssignmentId string = !empty(logAnalyticsWorkspaceName)
  ? healthModelLogAnalyticsReader.id
  : ''
output logAnalyticsDataReaderRoleAssignmentId string = !empty(logAnalyticsWorkspaceName)
  ? healthModelLogAnalyticsDataReader.id
  : ''
