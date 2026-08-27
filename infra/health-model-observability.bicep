targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Existing Foundry account entity that the workload depends on.')
@minLength(3)
param foundryEntityName string

@description('Health Model root entity.')
@minLength(3)
param rootEntityName string = 'foundry'

@description('Container App name used to scope Log Analytics queries.')
param containerAppName string

@description('Full ARM resource ID of workspace-based Application Insights.')
param appInsightsResourceId string

@description('Full ARM resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceResourceId string

@description('Action group that receives degraded and unhealthy workload alerts.')
@minLength(1)
param actionGroupResourceId string

@description('Existing Health Model authentication setting.')
param authenticationSettingName string = 'systemassigned'

var apiErrorRateQuery = '''
let result = AppRequests
    | where TimeGenerated > ago(15m)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | summarize Total = sum(ItemCount), Failed = sumif(ItemCount, Success == false)
    | extend ErrorRateBasisPoints = toint(iff(Total == 0, 0.0, todouble(Failed) / todouble(Total) * 10000.0))
    | project ErrorRateBasisPoints;
union result, (print ErrorRateBasisPoints = toint(0))
| summarize ErrorRateBasisPoints = max(ErrorRateBasisPoints)
'''

var apiP95DurationQuery = '''
let result = AppRequests
    | where TimeGenerated > ago(15m)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | summarize P95DurationMs = toint(coalesce(percentile(DurationMs, 95), 0.0));
union result, (print P95DurationMs = toint(0))
| summarize P95DurationMs = max(P95DurationMs)
'''

var otelFoundryServerErrorQuery = '''
let result = AppMetrics
    | where TimeGenerated > ago(15m)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | where Name == "foundry.server_errors"
    | summarize FoundryServerErrors = toint(sum(Sum));
union result, (print FoundryServerErrors = toint(0))
| summarize FoundryServerErrors = max(FoundryServerErrors)
'''

var runtimeConsoleErrorQuery = replace('''
let result = ContainerAppConsoleLogs_CL
    | where TimeGenerated > ago(15m)
    | where ContainerAppName_s == "{{containerAppName}}"
    | where Stream_s =~ "stderr"
        or Log_s has "fail:"
        or Log_s has "Unhandled exception"
    | summarize RuntimeErrors = count();
union result, (print RuntimeErrors = tolong(0))
| summarize RuntimeErrors = max(RuntimeErrors)
''', '{{containerAppName}}', containerAppName)

var ingressServerErrorQuery = replace('''
let result = ContainerAppHTTPLogs
    | where TimeGenerated > ago(15m)
    | where ContainerAppName == "{{containerAppName}}"
    | where StatusCode >= 500
    | summarize IngressServerErrors = count();
union result, (print IngressServerErrors = tolong(0))
| summarize IngressServerErrors = max(IngressServerErrors)
''', '{{containerAppName}}', containerAppName)

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' existing = {
  name: healthModelName
}

resource workloadEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'clinical-trial-workload'
  parent: healthModel
  properties: {
    displayName: 'Clinical Trial Chat Workload'
    impact: 'Standard'
    healthObjective: 99
    icon: {
      iconName: 'SystemComponent'
    }
    canvasPosition: {
      x: 20
      y: 360
    }
    alerts: {
      degraded: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Clinical Trial Chat workload health is degraded.'
        severity: 'Sev2'
      }
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Clinical Trial Chat workload is unhealthy and user impact is likely.'
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

resource appInsightsEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'application-insights-api'
  parent: healthModel
  properties: {
    displayName: 'Application Insights - API'
    impact: 'Standard'
    alerts: {
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Application Insights API health is unhealthy.'
        severity: 'Sev3'
      }
    }
    icon: {
      iconName: 'AppService'
    }
    canvasPosition: {
      x: -200
      y: 720
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: appInsightsResourceId
      }
      azureLogAnalytics: {
        authenticationSetting: authenticationSettingName
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            name: 'appinsights-api-error-rate'
            displayName: 'Application Insights API error rate'
            signalKind: 'LogAnalyticsQuery'
            queryText: apiErrorRateQuery
            valueColumnName: 'ErrorRateBasisPoints'
            dataUnit: 'BasisPoints'
            timeGrain: 'PT15M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 100
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 500
              }
            }
          }
          {
            name: 'appinsights-api-p95'
            displayName: 'Application Insights API P95 duration'
            signalKind: 'LogAnalyticsQuery'
            queryText: apiP95DurationQuery
            valueColumnName: 'P95DurationMs'
            dataUnit: 'MilliSeconds'
            timeGrain: 'PT15M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 15000
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 30000
              }
            }
          }
        ]
      }
    }
  }
}

resource openTelemetryEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'opentelemetry-dependencies'
  parent: healthModel
  properties: {
    displayName: 'OpenTelemetry - Foundry'
    impact: 'Standard'
    alerts: {
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'OpenTelemetry Foundry dependency health is unhealthy.'
        severity: 'Sev3'
      }
    }
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: 180
      y: 720
    }
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: authenticationSettingName
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            name: 'otel-foundry-server-errors'
            displayName: 'OpenTelemetry Foundry HTTP 5xx errors'
            signalKind: 'LogAnalyticsQuery'
            queryText: otelFoundryServerErrorQuery
            valueColumnName: 'FoundryServerErrors'
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
                threshold: 3
              }
            }
          }
        ]
      }
    }
  }
}

resource logAnalyticsEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'log-analytics-runtime'
  parent: healthModel
  properties: {
    displayName: 'Log Analytics - Runtime'
    impact: 'Standard'
    alerts: {
      unhealthy: {
        actionGroupIds: [
          actionGroupResourceId
        ]
        description: 'Log Analytics runtime health is unhealthy.'
        severity: 'Sev3'
      }
    }
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: 450
      y: 560
    }
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: authenticationSettingName
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            name: 'runtime-console-errors'
            displayName: 'Container runtime errors'
            signalKind: 'LogAnalyticsQuery'
            queryText: runtimeConsoleErrorQuery
            valueColumnName: 'RuntimeErrors'
            dataUnit: 'Count'
            timeGrain: 'PT15M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 5
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 20
              }
            }
          }
          {
            name: 'runtime-ingress-server-errors'
            displayName: 'Container ingress 5xx responses'
            signalKind: 'LogAnalyticsQuery'
            queryText: ingressServerErrorQuery
            valueColumnName: 'IngressServerErrors'
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
        ]
      }
    }
  }
}

resource alertingEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'azure-monitor-alerting'
  parent: healthModel
  properties: {
    displayName: 'Azure Monitor Alerting'
    impact: 'Suppressed'
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: 600
      y: 420
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: actionGroupResourceId
      }
    }
  }
}

// Keep the original resource names so incremental deployments replace the
// reversed relationships instead of leaving a cycle in the model.
resource workloadFoundryRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'foundry-to-workload'
  parent: healthModel
  properties: {
    parentEntityName: workloadEntity.name
    childEntityName: foundryEntityName
    displayName: 'Workload to Microsoft Foundry'
  }
}

resource rootWorkloadRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'root-to-foundry'
  parent: healthModel
  properties: {
    parentEntityName: rootEntityName
    childEntityName: workloadEntity.name
    displayName: 'Health Model root to workload'
  }
}

resource workloadAppInsightsRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'workload-to-application-insights'
  parent: healthModel
  properties: {
    parentEntityName: workloadEntity.name
    childEntityName: appInsightsEntity.name
    displayName: 'Workload to Application Insights'
  }
}

resource workloadOpenTelemetryRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'workload-to-opentelemetry'
  parent: healthModel
  properties: {
    parentEntityName: workloadEntity.name
    childEntityName: openTelemetryEntity.name
    displayName: 'Workload to OpenTelemetry'
  }
}

resource workloadLogAnalyticsRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'workload-to-log-analytics'
  parent: healthModel
  properties: {
    parentEntityName: workloadEntity.name
    childEntityName: logAnalyticsEntity.name
    displayName: 'Workload to Log Analytics'
  }
}

resource workloadAlertingRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'workload-to-alerting'
  parent: healthModel
  properties: {
    parentEntityName: workloadEntity.name
    childEntityName: alertingEntity.name
    displayName: 'Workload to alerting'
  }
}

output workloadEntityName string = workloadEntity.name
output configuredEntityCount int = 5
output configuredSignalCount int = 5
output configuredRelationshipCount int = 6
