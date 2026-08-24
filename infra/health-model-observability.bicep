targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Existing Foundry account entity that will parent the workload health entity.')
@minLength(3)
param foundryEntityName string

@description('Full ARM resource ID of the Container App API.')
param containerAppResourceId string

@description('Container App name used to scope Log Analytics queries.')
param containerAppName string

@description('Full ARM resource ID of workspace-based Application Insights.')
param appInsightsResourceId string

@description('Full ARM resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceResourceId string

@description('Action group that receives degraded and unhealthy workload alerts.')
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
union result, (print ErrorRateBasisPoints = 0)
| summarize ErrorRateBasisPoints = max(ErrorRateBasisPoints)
'''

var apiP95DurationQuery = '''
let result = AppRequests
    | where TimeGenerated > ago(15m)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | summarize P95DurationMs = toint(coalesce(percentile(DurationMs, 95), 0.0));
union result, (print P95DurationMs = 0)
| summarize P95DurationMs = max(P95DurationMs)
'''

var otelDependencyFailureQuery = '''
let result = AppDependencies
    | where TimeGenerated > ago(15m)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | where Name in (
        "foundry.chat.complete",
        "conversation.context.read",
        "conversation.exchange.write",
        "conversation.history.read",
        "conversation.history.delete")
    | summarize DependencyFailures = toint(sumif(ItemCount, Success == false));
union result, (print DependencyFailures = 0)
| summarize DependencyFailures = max(DependencyFailures)
'''

var runtimeConsoleErrorQuery = replace('''
let result = ContainerAppConsoleLogs_CL
    | where TimeGenerated > ago(15m)
    | where ContainerAppName_s == "{{containerAppName}}"
    | where Stream_s =~ "stderr"
        or Log_s has "fail:"
        or Log_s has "Unhandled exception"
    | summarize RuntimeErrors = count();
union result, (print RuntimeErrors = 0)
| summarize RuntimeErrors = max(RuntimeErrors)
''', '{{containerAppName}}', containerAppName)

var ingressServerErrorQuery = replace('''
let result = ContainerAppHTTPLogs
    | where TimeGenerated > ago(15m)
    | where ContainerAppName == "{{containerAppName}}"
    | where StatusCode >= 500
    | summarize IngressServerErrors = count();
union result, (print IngressServerErrors = 0)
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

resource azureMonitorEntity 'Microsoft.CloudHealth/healthmodels/entities@2026-05-01-preview' = {
  name: 'azure-monitor-api'
  parent: healthModel
  properties: {
    displayName: 'Azure Monitor - Container App'
    impact: 'Standard'
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: -360
      y: 560
    }
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: containerAppResourceId
        signals: [
          {
            name: 'api-response-time'
            displayName: 'Container App response time'
            signalKind: 'AzureResourceMetric'
            metricNamespace: 'microsoft.app/containerapps'
            metricName: 'ResponseTime'
            aggregationType: 'Average'
            dataUnit: 'MilliSeconds'
            timeGrain: 'PT15M'
            refreshInterval: 'PT5M'
            evaluationRules: {
              degradedRule: {
                operator: 'GreaterThan'
                threshold: 2000
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 5000
              }
            }
          }
          {
            name: 'api-server-errors'
            displayName: 'Container App 5xx responses'
            signalKind: 'AzureResourceMetric'
            metricNamespace: 'microsoft.app/containerapps'
            metricName: 'Requests'
            dimensionFilter: 'statusCodeCategory eq \'5xx\''
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
        ]
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
    icon: {
      iconName: 'AppService'
    }
    canvasPosition: {
      x: -120
      y: 560
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
                threshold: 2000
              }
              unhealthyRule: {
                operator: 'GreaterThan'
                threshold: 5000
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
    displayName: 'OpenTelemetry Dependencies'
    impact: 'Standard'
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: 120
      y: 560
    }
    signalGroups: {
      azureLogAnalytics: {
        authenticationSetting: authenticationSettingName
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
        signals: [
          {
            name: 'otel-dependency-failures'
            displayName: 'OpenTelemetry dependency failures'
            signalKind: 'LogAnalyticsQuery'
            queryText: otelDependencyFailureQuery
            valueColumnName: 'DependencyFailures'
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
    icon: {
      iconName: 'Resource'
    }
    canvasPosition: {
      x: 360
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

resource foundryWorkloadRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'foundry-to-workload'
  parent: healthModel
  properties: {
    parentEntityName: foundryEntityName
    childEntityName: workloadEntity.name
    displayName: 'Foundry to workload health'
  }
}

resource workloadAzureMonitorRelationship 'Microsoft.CloudHealth/healthmodels/relationships@2026-05-01-preview' = {
  name: 'workload-to-azure-monitor'
  parent: healthModel
  properties: {
    parentEntityName: workloadEntity.name
    childEntityName: azureMonitorEntity.name
    displayName: 'Workload to Azure Monitor'
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

output workloadEntityName string = workloadEntity.name
output configuredEntityCount int = 5
output configuredSignalCount int = 7
output configuredRelationshipCount int = 5
