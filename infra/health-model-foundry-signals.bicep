targetScope = 'resourceGroup'

@description('Name of the existing Microsoft.CloudHealth health model.')
@minLength(3)
param healthModelName string

@description('Name of the existing entity that represents the Foundry account.')
@minLength(3)
param foundryEntityName string

@description('Full ARM resource ID of the Microsoft.CognitiveServices account.')
param foundryResourceId string

@description('Foundry model deployment used by this application.')
@minLength(1)
param modelDeploymentName string

@description('Existing Health Model authentication setting used by the entity.')
param authenticationSettingName string = 'systemassigned'

@description('Entity display name.')
param foundryEntityDisplayName string = 'Microsoft Foundry'

@description('Include filtered 4xx, 5xx, and 429 signals. Leave false until each status-code series has emitted data; an absent series can evaluate as Unknown.')
param includeSparseErrorSignals bool = true

var deploymentFilter = 'ModelDeploymentName eq \'${modelDeploymentName}\''
var metricNamespace = 'microsoft.cognitiveservices/accounts'

var coreSignals = [
  {
    name: 'foundry-availability'
    displayName: 'Foundry deployment availability'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'AzureOpenAIAvailabilityRate'
    dimensionFilter: deploymentFilter
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
    dimensionFilter: deploymentFilter
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

var sparseErrorSignals = [
  {
    name: 'foundry-server-errors'
    displayName: 'Foundry server errors'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'AzureOpenAIRequests'
    dimensionFilter: 'StatusCode eq \'500\' or StatusCode eq \'502\' or StatusCode eq \'503\' or StatusCode eq \'504\' and ${deploymentFilter}'
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
    name: 'foundry-throttled-requests'
    displayName: 'Foundry throttled requests'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'AzureOpenAIRequests'
    dimensionFilter: '${deploymentFilter} and StatusCode eq \'429\''
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT5M'
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
    name: 'foundry-client-errors'
    displayName: 'Foundry client integration errors'
    signalKind: 'AzureResourceMetric'
    metricNamespace: metricNamespace
    metricName: 'AzureOpenAIRequests'
    dimensionFilter: 'StatusCode eq \'400\' or StatusCode eq \'401\' or StatusCode eq \'403\' or StatusCode eq \'404\' or StatusCode eq \'408\' or StatusCode eq \'409\' or StatusCode eq \'422\' and ${deploymentFilter}'
    aggregationType: 'Total'
    dataUnit: 'Count'
    timeGrain: 'PT15M'
    refreshInterval: 'PT5M'
    evaluationRules: {
      degradedRule: {
        operator: 'GreaterThan'
        threshold: 2
      }
      unhealthyRule: {
        operator: 'GreaterThan'
        threshold: 10
      }
    }
  }
]

resource healthModel 'Microsoft.CloudHealth/healthmodels@2026-05-01-preview' existing = {
  name: healthModelName
}

// Entity PUT operations replace the complete signalGroups value. Keep this file
// as the source of truth for every signal that should remain on this entity.
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
      x: -300
      y: 200
    }
    healthObjective: 99
    signalGroups: {
      azureResource: {
        authenticationSetting: authenticationSettingName
        azureResourceId: foundryResourceId
        resourceHealth: {
          enabled: 'Enabled'
        }
        signals: concat(
          coreSignals,
          includeSparseErrorSignals ? sparseErrorSignals : []
        )
      }
    }
  }
}

output entityResourceId string = foundryEntity.id
output configuredSignalCount int = length(coreSignals) + (includeSparseErrorSignals ? length(sparseErrorSignals) : 0)
