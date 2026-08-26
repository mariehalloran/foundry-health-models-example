targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Name of the existing entity that represents the Foundry account.')
@minLength(3)
param foundryEntityName string

@description('Full ARM resource ID of the Microsoft.CognitiveServices account.')
param foundryResourceId string

@description('Action group that receives degraded and unhealthy Foundry alerts.')
@minLength(1)
param actionGroupResourceId string

@description('Existing Health Model authentication setting used by the entities.')
param authenticationSettingName string = 'systemassigned'

@description('Entity display name.')
param foundryEntityDisplayName string = 'Microsoft Foundry'

@description('Inference-token count in 15 minutes that degrades the Foundry entity.')
@minValue(1)
param tokenUsageDegradedThreshold int = 25000

@description('Inference-token count in 15 minutes that makes the Foundry entity unhealthy.')
@minValue(1)
param tokenUsageUnhealthyThreshold int = 50000

var metricNamespace = 'microsoft.cognitiveservices/accounts'

var coreSignals = [
  {
    name: 'foundry-availability'
    displayName: 'Foundry availability'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'AzureOpenAIAvailabilityRate'
    aggregationType: 'Average'
    dataUnit: 'Percent'
    timeGrain: 'PT15M'
    refreshInterval: 'PT5M'
    evaluationRules: {
      degradedRule: {
        operator: 'LessThan'
        threshold: 99
      }
      unhealthyRule: {
        operator: 'LessThan'
        threshold: 95
      }
    }
  }
  {
    name: 'foundry-latency'
    displayName: 'Foundry time to last token'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'AzureOpenAITTLTInMS'
    aggregationType: 'Average'
    dataUnit: 'MilliSeconds'
    timeGrain: 'PT15M'
    refreshInterval: 'PT5M'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 500
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 10000
      }
    }
  }
]

var safetySignals = [
  {
    name: 'foundry-harmful-requests'
    displayName: 'Foundry harmful requests detected'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'RAIHarmfulRequests'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT15M'
    refreshInterval: 'PT5M'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 0
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 5
      }
    }
  }
  {
    name: 'foundry-rejected-requests'
    displayName: 'Foundry requests blocked by content filters'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'RAIRejectedRequests'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT15M'
    refreshInterval: 'PT5M'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 0
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 10
      }
    }
  }
]

var usageSignals = [
  {
    name: 'foundry-inference-tokens'
    displayName: 'Foundry inference token consumption'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'TokenTransaction'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT15M'
    refreshInterval: 'PT5M'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: tokenUsageDegradedThreshold
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: tokenUsageUnhealthyThreshold
      }
    }
  }
]

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' existing = {
  name: healthModelName
}

// Entity PUT operations replace the complete signalGroups value. Keep this file
// as the source of truth for every Foundry signal that should remain.
resource foundryEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: foundryEntityName
  parent: healthModel
  properties: {
    displayName: foundryEntityDisplayName
    impact: 'Standard'
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: -360
      y: 420
    }
    healthObjective: 99
    alerts: {
      degraded: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Microsoft Foundry health is degraded.'
        severity: 'Sev2'
      }
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Microsoft Foundry is unhealthy and user impact is likely.'
        severity: 'Sev1'
      }
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        resourceHealth: {
          enabled: 'Enabled'
        }
        signals: concat(coreSignals, safetySignals, usageSignals)
      }
    }
  }
}

output entityResourceId string = foundryEntity.id
output configuredEntityCount int = 1
output configuredSignalCount int = length(coreSignals) + length(safetySignals) + length(usageSignals)
output configuredRelationshipCount int = 0
