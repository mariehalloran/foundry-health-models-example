targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Name of the existing entity that represents the Foundry account.')
@minLength(3)
param foundryEntityName string

@description('Full ARM resource ID of the Microsoft.CognitiveServices account.')
param foundryResourceId string

@description('Existing Health Model authentication setting used by the entities.')
param authenticationSettingName string = 'systemassigned'

@description('Entity display name.')
param foundryEntityDisplayName string = 'Foundry Availability - Azure Metrics'

@description('Minimum Azure OpenAI requests in five minutes before platform availability can affect health.')
@minValue(1)
param foundryPlatformMinimumRequests int = 20

@description('Platform availability percentage that degrades Foundry health. Keep this above the unhealthy percentage.')
@minValue(0)
@maxValue(100)
param foundryPlatformDegradedAvailabilityPercent int = 99

@description('Platform availability percentage that makes Foundry health unhealthy. Keep this below the degraded percentage.')
@minValue(0)
@maxValue(100)
param foundryPlatformUnhealthyAvailabilityPercent int = 95

var foundryMetricNamespace = 'microsoft.cognitiveservices/accounts'
var foundryPlatformAvailabilitySignalName = 'foundry-platform-availability'
var foundryPlatformVolumeGateSignalName = 'foundry-platform-volume-gate'
var foundryPlatformReliabilitySignals = [
  {
    name: foundryPlatformAvailabilitySignalName
    displayName: 'AzureOpenAIAvailabilityRate'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'AzureOpenAIAvailabilityRate'
    aggregationType: 'Average'
    dataUnit: 'Percent'
    timeGrain: 'PT5M'
    refreshInterval: 'PT1M'
    evaluationRules: {
      degradedRule: {
        operator: 'LessThanOrEqual'
        threshold: foundryPlatformDegradedAvailabilityPercent
      }
      unhealthyRule: {
        operator: 'LessThanOrEqual'
        threshold: foundryPlatformUnhealthyAvailabilityPercent
      }
    }
  }
  {
    name: foundryPlatformVolumeGateSignalName
    displayName: 'AzureOpenAIRequests'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'AzureOpenAIRequests'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT1M'
    evaluationRules: {
      unhealthyRule: {
        operator: 'GreaterThanOrEqual'
        threshold: foundryPlatformMinimumRequests
      }
    }
  }
]

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' existing = {
  name: healthModelName
}

// Entity PUT operations replace the complete signalGroups value.
// Signal aggregation groups require 2026-09-01-preview, which can be newer than the bundled Bicep type index.
#disable-next-line BCP081
resource foundryEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-09-01-preview' = {
  name: foundryEntityName
  parent: healthModel
  properties: {
    displayName: foundryEntityDisplayName
    impact: 'Standard'
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: -400
      y: 420
    }
    healthObjective: 99
    alerts: {}
    signalAggregationGroups: [
      {
        name: 'foundry-platform-reliability-gate'
        displayName: 'Foundry platform reliability with minimum traffic'
        aggregationType: 'BestOf'
        members: [
          foundryPlatformAvailabilitySignalName
          foundryPlatformVolumeGateSignalName
        ]
      }
    ]
    signalGroups: {
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        resourceHealth: {
          enabled: 'Disabled'
        }
        signals: foundryPlatformReliabilitySignals
      }
    }
  }
}

output entityResourceId string = foundryEntity.id
output configuredEntityCount int = 1
output configuredSignalCount int = 2
output configuredRelationshipCount int = 0
