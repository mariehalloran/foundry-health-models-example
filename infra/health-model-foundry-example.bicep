targetScope = 'resourceGroup'

@description('Azure resource name for the Health Model. Spaces are not supported.')
@minLength(3)
param healthModelName string = 'Foundry-Example'

@description('Azure region for the Health Model resource.')
param healthModelLocation string = 'centralus'

@description('Full ARM resource ID of the Microsoft.CognitiveServices account.')
param foundryResourceId string

@description('Name of the Log Analytics workspace used by the Application OTEL signals.')
@minLength(3)
param logAnalyticsWorkspaceName string

@description('Full ARM resource ID of the Action Group that receives Health Model alerts.')
@minLength(1)
param actionGroupResourceId string

@description('Minimum requests in five minutes before availability can affect health.')
@minValue(1)
param minimumRequests int = 20

@description('Availability percentage that degrades Foundry health.')
@minValue(0)
@maxValue(100)
param degradedAvailabilityPercent int = 99

@description('Availability percentage that makes Foundry health unhealthy.')
@minValue(0)
@maxValue(100)
param unhealthyAvailabilityPercent int = 95

var authenticationSettingName = 'systemassigned'
var foundryAvailabilityEntityName = 'foundry-availability-azure-metrics'

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' = {
  name: healthModelName
  location: healthModelLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource systemAssignedAuthentication 'Microsoft.CloudHealth/healthmodels/authenticationsettings@2026-05-01-preview' = {
  name: authenticationSettingName
  parent: healthModel
  properties: {
    authenticationKind: 'ManagedIdentity'
    displayName: 'System-assigned identity'
    managedIdentityName: 'SystemAssigned'
  }
}

module healthModelAccess 'health-model-metrics.bicep' = {
  name: 'foundry-example-access'
  params: {
    healthModelName: healthModel.name
    healthModelResourceGroupName: resourceGroup().name
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
  }
  dependsOn: [
    systemAssignedAuthentication
  ]
}

module foundrySignals 'health-model-foundry-signals.bicep' = {
  name: 'foundry-example-platform-signals'
  params: {
    healthModelName: healthModel.name
    foundryEntityName: foundryAvailabilityEntityName
    foundryResourceId: foundryResourceId
    authenticationSettingName: systemAssignedAuthentication.name
    foundryPlatformMinimumRequests: minimumRequests
    foundryPlatformDegradedAvailabilityPercent: degradedAvailabilityPercent
    foundryPlatformUnhealthyAvailabilityPercent: unhealthyAvailabilityPercent
  }
  dependsOn: [
    healthModelAccess
  ]
}

module observability 'health-model-observability.bicep' = {
  name: 'foundry-example-observability'
  params: {
    healthModelName: healthModel.name
    foundryEntityName: foundryAvailabilityEntityName
    foundryResourceId: foundryResourceId
    rootEntityName: toLower(healthModel.name)
    rootEntityDisplayName: 'Foundry Workload'
    logAnalyticsWorkspaceResourceId: resourceId(
      'Microsoft.OperationalInsights/workspaces',
      logAnalyticsWorkspaceName
    )
    actionGroupResourceId: actionGroupResourceId
    authenticationSettingName: systemAssignedAuthentication.name
    otelReliabilityMinimumRequests: minimumRequests
    otelDegradedAvailabilityPercent: degradedAvailabilityPercent
    otelUnhealthyAvailabilityPercent: unhealthyAvailabilityPercent
  }
  dependsOn: [
    foundrySignals
  ]
}

output healthModelResourceId string = healthModel.id
output healthModelName string = healthModel.name
output configuredEntityCount int = 1 + observability.outputs.configuredEntityCount
output configuredSignalCount int = 2 + observability.outputs.configuredSignalCount
output configuredRelationshipCount int = observability.outputs.configuredRelationshipCount
