targetScope = 'resourceGroup'

@description('Short name for the existing deployment environment.')
@minLength(1)
@maxLength(32)
param environmentName string

@description('Azure region of the existing Container Apps environment and Foundry account.')
param location string

@description('Name of the existing Azure Container Registry.')
param containerRegistryName string

@description('Name of the existing Container Apps managed environment.')
param containerEnvironmentName string

@description('Name of the existing Microsoft Foundry account.')
param foundryAccountName string

@description('Name of the existing Foundry model deployment.')
param modelDeploymentName string

@description('Probe container image. Supply an immutable ACR tag for direct deployments.')
param probeImage string = 'mcr.microsoft.com/k8se/quickstart-jobs:latest'

var resourceToken = toLower(
  uniqueString(subscription().id, resourceGroup().id, location, environmentName)
)
var commonTags = {
  'azd-env-name': environmentName
  application: 'clinical-trial-chat'
  component: 'foundry-health-probe'
}
var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)
var openAiUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
)

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: containerEnvironmentName
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource probeManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'azidp${resourceToken}'
  location: location
  tags: commonTags
}

resource probeAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, probeManagedIdentity.id, acrPullRoleDefinitionId)
  scope: containerRegistry
  properties: {
    principalId: probeManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource probeFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, probeManagedIdentity.id, openAiUserRoleDefinitionId)
  scope: foundry
  properties: {
    principalId: probeManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAiUserRoleDefinitionId
  }
}

resource foundryHealthProbeJob 'Microsoft.App/jobs@2025-01-01' = {
  name: 'azjob${resourceToken}'
  location: location
  tags: union(commonTags, {
    'azd-service-name': 'probe'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${probeManagedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 55
      replicaRetryLimit: 0
      scheduleTriggerConfig: {
        cronExpression: '* * * * *'
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: probeManagedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'probe'
          image: probeImage
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: probeManagedIdentity.properties.clientId
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: 'https://${foundry.name}.openai.azure.com/'
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: modelDeploymentName
            }
            {
              name: 'PROBE_TIMEOUT_SECONDS'
              value: '45'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
  dependsOn: [
    probeAcrPullRole
    probeFoundryRole
  ]
}

output jobName string = foundryHealthProbeJob.name
output managedIdentityName string = probeManagedIdentity.name
