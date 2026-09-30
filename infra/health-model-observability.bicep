targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Existing Foundry account entity.')
@minLength(3)
param foundryEntityName string

@description('Full ARM resource ID of the Microsoft.CognitiveServices account.')
param foundryResourceId string

@description('Stable resource name for the Foundry diagnostics metrics entity.')
@minLength(3)
param foundryDiagnosticsEntityName string = 'foundry-diagnostics'

@description('Health Model root entity.')
@minLength(3)
param rootEntityName string = 'foundry'

@description('Display name for the Health Model root entity.')
@minLength(3)
param rootEntityDisplayName string = 'Foundry Health Model Example'

@description('Full ARM resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceResourceId string

@description('Action group that receives Health Model alerts.')
@minLength(1)
param actionGroupResourceId string

@description('Existing Health Model authentication setting.')
param authenticationSettingName string = 'systemassigned'

@description('Minimum OTEL Foundry requests in five completed minutes before availability can affect health.')
@minValue(1)
param otelReliabilityMinimumRequests int = 20

@description('OTEL availability percentage that degrades reliability. Keep this above the unhealthy percentage.')
@minValue(0)
@maxValue(100)
param otelDegradedAvailabilityPercent int = 99

@description('OTEL availability percentage that makes reliability unhealthy. Keep this below the degraded percentage.')
@minValue(0)
@maxValue(100)
param otelUnhealthyAvailabilityPercent int = 95

var foundryMetricNamespace = 'microsoft.cognitiveservices/accounts'
var foundryDiagnosticEvaluationRules = {
  unhealthyRule: {
    operator: 'Dynamic'
    sensitivity: 'Low'
    lookBackWindow: 'PT1H'
  }
}
var foundryDiagnosticSignals = [
  {
    name: 'foundry-diagnostic-token-transaction'
    displayName: 'TokenTransaction'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'TokenTransaction'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-time-between-tokens'
    displayName: 'AzureOpenAINormalizedTBTInMS'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'AzureOpenAINormalizedTBTInMS'
    aggregationType: 'Average'
    dataUnit: 'MilliSeconds'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-generated-tokens'
    displayName: 'GeneratedTokens'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'GeneratedTokens'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-time-to-last-byte'
    displayName: 'AzureOpenAITTLTInMS'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'AzureOpenAITTLTInMS'
    aggregationType: 'Average'
    dataUnit: 'MilliSeconds'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-normalized-first-byte'
    displayName: 'AzureOpenAINormalizedTTFTInMS'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'AzureOpenAINormalizedTTFTInMS'
    aggregationType: 'Average'
    dataUnit: 'MilliSeconds'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-prompt-tokens'
    displayName: 'ProcessedPromptTokens'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'ProcessedPromptTokens'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-blocked'
    displayName: 'RAIRejectedRequests'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'RAIRejectedRequests'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-harmful'
    displayName: 'RAIHarmfulRequests'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'RAIHarmfulRequests'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-safety-event'
    displayName: 'RAISystemEvent'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'RAISystemEvent'
    aggregationType: 'Average'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
  {
    name: 'foundry-diagnostic-safety-volume'
    displayName: 'RAITotalRequests'
    signalKind: 'AzureResourceMetric'
    metricNamespace: foundryMetricNamespace
    metricName: 'RAITotalRequests'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
    refreshInterval: 'PT5M'
    evaluationRules: foundryDiagnosticEvaluationRules
  }
]
var otelAvailabilitySignalName = 'otel-foundry-availability'
var otelVolumeGateSignalName = 'otel-foundry-volume-gate'
var otelAvailabilityQuery = '''
let EvaluationEnd = ago(2m);
AppMetrics
    | where TimeGenerated between (EvaluationEnd - 5m .. EvaluationEnd)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | where Name in ("foundry.requests", "foundry.server_errors")
    | summarize
        Total = tolong(sumif(Sum, Name == "foundry.requests")),
        ServerErrors = tolong(sumif(Sum, Name == "foundry.server_errors"))
    | project AvailabilityPercent = toint(
        iff(
            Total == 0,
            100.0,
            todouble(Total - ServerErrors) / todouble(Total) * 100.0))
'''
var otelRequestCountQuery = '''
let EvaluationEnd = ago(2m);
AppMetrics
    | where TimeGenerated between (EvaluationEnd - 5m .. EvaluationEnd)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | where Name == "foundry.requests"
    | summarize RequestCount = tolong(sum(Sum))
'''

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' existing = {
  name: healthModelName
}

resource rootEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: rootEntityName
  parent: healthModel
  properties: {
    displayName: rootEntityDisplayName
    impact: 'Standard'
    canvasPosition: {
      x: 200
      y: 0
    }
    alerts: {}
    signalGroups: {
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource availabilityEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'reliability'
  parent: healthModel
  properties: {
    displayName: 'Foundry Availability'
    impact: 'Standard'
    healthObjective: 99
    icon: {
      iconName: 'SystemComponent'
    }
    canvasPosition: {
      x: -200
      y: 180
    }
    alerts: {
      degraded: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry availability is degraded.'
        severity: 'Sev2'
      }
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry availability is unhealthy and user impact is likely.'
        severity: 'Sev1'
      }
    }
    signalGroups: {
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource diagnosticsEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'diagnostics'
  parent: healthModel
  properties: {
    displayName: 'Foundry Diagnostics'
    impact: 'Suppressed'
    icon: {
      iconName: 'Analysis'
    }
    canvasPosition: {
      x: 600
      y: 180
    }
    alerts: {
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Foundry diagnostics detected a significant anomaly.'
        severity: 'Sev3'
      }
    }
    signalGroups: {
      dependencies: {
        aggregationType: 'WorstOf'
        ignoreUnknown: true
      }
    }
  }
}

resource foundryDiagnosticsEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: foundryDiagnosticsEntityName
  parent: healthModel
  properties: {
    displayName: 'Diagnostics - Azure Metrics'
    impact: 'Standard'
    alerts: {}
    icon: {
      iconName: 'Analysis'
    }
    canvasPosition: {
      x: 600
      y: 420
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        signals: foundryDiagnosticSignals
      }
    }
  }
}

// Signal aggregation groups require 2026-09-01-preview, which can be newer than the bundled Bicep type index.
#disable-next-line BCP081
resource otelAvailabilityEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-09-01-preview' = {
  name: 'log-analytics-runtime'
  parent: healthModel
  properties: {
    displayName: 'Foundry Availability - Application OTEL'
    impact: 'Standard'
    alerts: {}
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: 0
      y: 420
    }
    signalAggregationGroups: [
      {
        name: 'otel-reliability-gate'
        displayName: 'OTEL availability with minimum traffic'
        aggregationType: 'BestOf'
        members: [
          otelAvailabilitySignalName
          otelVolumeGateSignalName
        ]
      }
    ]
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: authenticationSettingName
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            name: otelAvailabilitySignalName
            displayName: 'foundry.availability_rate'
            signalKind: 'LogAnalyticsQuery'
            queryText: otelAvailabilityQuery
            valueColumnName: 'AvailabilityPercent'
            dataUnit: 'Percent'
            timeGrain: 'PT5M'
            refreshInterval: 'PT1M'
            evaluationRules: {
              degradedRule: {
                operator: 'LessThanOrEqual'
                threshold: otelDegradedAvailabilityPercent
              }
              unhealthyRule: {
                operator: 'LessThanOrEqual'
                threshold: otelUnhealthyAvailabilityPercent
              }
            }
          }
          {
            name: otelVolumeGateSignalName
            displayName: 'foundry.requests'
            signalKind: 'LogAnalyticsQuery'
            queryText: otelRequestCountQuery
            valueColumnName: 'RequestCount'
            dataUnit: 'Count'
            timeGrain: 'PT5M'
            refreshInterval: 'PT1M'
            evaluationRules: {
              unhealthyRule: {
                operator: 'GreaterThanOrEqual'
                threshold: otelReliabilityMinimumRequests
              }
            }
          }
        ]
      }
    }
  }
}

resource rootAvailabilityRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'health-root-to-reliability'
  parent: healthModel
  properties: {
    parentEntityName: rootEntity.name
    childEntityName: availabilityEntity.name
    displayName: 'Foundry Availability'
  }
}

resource rootDiagnosticsRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'health-root-to-diagnostics'
  parent: healthModel
  properties: {
    parentEntityName: rootEntity.name
    childEntityName: diagnosticsEntity.name
    displayName: 'Foundry Diagnostics'
  }
}

resource availabilityMetricsRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'reliability-to-foundry'
  parent: healthModel
  properties: {
    parentEntityName: availabilityEntity.name
    childEntityName: foundryEntityName
    displayName: 'Foundry Availability - Azure Metrics'
  }
}

resource availabilityOtelRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'reliability-to-otel'
  parent: healthModel
  properties: {
    parentEntityName: availabilityEntity.name
    childEntityName: otelAvailabilityEntity.name
    displayName: 'Foundry Availability - Application OTEL'
  }
}

resource diagnosticsMetricsRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'diagnostics-to-foundry-metrics'
  parent: healthModel
  properties: {
    parentEntityName: diagnosticsEntity.name
    childEntityName: foundryDiagnosticsEntity.name
    displayName: 'Diagnostics - Azure Metrics'
  }
}

output configuredEntityCount int = 4
output configuredSignalCount int = 12
output configuredRelationshipCount int = 5
