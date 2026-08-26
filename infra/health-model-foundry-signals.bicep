targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Name of the existing entity that represents the Foundry account.')
@minLength(3)
param foundryEntityName string

@description('Full ARM resource ID of the Microsoft.CognitiveServices account.')
param foundryResourceId string

@description('Action group that receives Foundry safety and usage alerts.')
@minLength(1)
param actionGroupResourceId string

@description('Existing Health Model authentication setting used by the entities.')
param authenticationSettingName string = 'systemassigned'

@description('Entity display name.')
param foundryEntityDisplayName string = 'Microsoft Foundry'

@description('Inference-token count in 15 minutes that degrades the Foundry usage entity.')
@minValue(1)
param tokenUsageDegradedThreshold int = 25000

@description('Inference-token count in 15 minutes that makes the Foundry usage entity unhealthy.')
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
        threshold: 5000
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
// as the source of truth for every signal group that should remain on this entity.
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
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        resourceHealth: {
          enabled: 'Enabled'
        }
      }
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource azureMonitorEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'azure-monitor-api'
  parent: healthModel
  properties: {
    displayName: 'Azure Monitor - Foundry Inference'
    impact: 'Standard'
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: -560
      y: 640
    }
    healthObjective: 99
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        signals: coreSignals
      }
    }
  }
}

resource safetyEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'foundry-safety'
  parent: healthModel
  properties: {
    displayName: 'Foundry Safety'
    impact: 'Suppressed'
    icon: {
      iconName: 'Shield'
    }
    canvasPosition: {
      x: -360
      y: 640
    }
    alerts: {
      degraded: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry detected harmful content or blocked a request.'
        severity: 'Sev3'
      }
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry safety events exceeded the configured threshold.'
        severity: 'Sev2'
      }
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        signals: safetySignals
      }
    }
  }
}

resource usageEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'foundry-usage'
  parent: healthModel
  properties: {
    displayName: 'Foundry Usage'
    impact: 'Suppressed'
    icon: {
      iconName: 'Gauge'
    }
    canvasPosition: {
      x: -160
      y: 640
    }
    alerts: {
      degraded: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry token consumption is elevated.'
        severity: 'Sev3'
      }
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry token consumption exceeded the configured threshold.'
        severity: 'Sev2'
      }
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        signals: usageSignals
      }
    }
  }
}

// Keep this resource name so incremental deployments correct the existing
// relationship instead of leaving a duplicate relationship in the model.
resource foundryAzureMonitorRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'workload-to-azure-monitor'
  parent: healthModel
  properties: {
    parentEntityName: foundryEntity.name
    childEntityName: azureMonitorEntity.name
    displayName: 'Foundry to Azure Monitor inference health'
  }
}

resource foundrySafetyRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'foundry-to-safety'
  parent: healthModel
  properties: {
    parentEntityName: foundryEntity.name
    childEntityName: safetyEntity.name
    displayName: 'Foundry to safety monitoring'
  }
}

resource foundryUsageRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'foundry-to-usage'
  parent: healthModel
  properties: {
    parentEntityName: foundryEntity.name
    childEntityName: usageEntity.name
    displayName: 'Foundry to usage monitoring'
  }
}

output entityResourceId string = foundryEntity.id
output azureMonitorEntityResourceId string = azureMonitorEntity.id
output safetyEntityResourceId string = safetyEntity.id
output usageEntityResourceId string = usageEntity.id
output configuredEntityCount int = 4
output configuredSignalCount int = length(coreSignals) + length(safetySignals) + length(usageSignals)
output configuredRelationshipCount int = 3
