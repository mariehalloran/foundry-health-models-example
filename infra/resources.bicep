targetScope = 'resourceGroup'

param environmentName string
param location string
param principalId string
param budgetContactEmail string
param monthlyBudgetAmount int
param modelCapacity int
param memoryRetentionDays int
param budgetStartDate string

var resourceToken = toLower(
  uniqueString(subscription().id, resourceGroup().id, location, environmentName)
)
var commonTags = {
  'azd-env-name': environmentName
  application: 'clinical-trial-chat'
  'cost-control': 'monthly-budget'
}
var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)
var openAiUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
)
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'
var cosmosDatabaseName = 'azdb${resourceToken}'
var cosmosContainerName = 'azct${resourceToken}'
var modelDeploymentName = 'azdep${resourceToken}'
var memoryRetentionSeconds = memoryRetentionDays * 24 * 60 * 60
var foundryPrivateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: 'azbud${resourceToken}'
  properties: {
    amount: monthlyBudgetAmount
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      Actual50: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: [
          budgetContactEmail
        ]
        contactRoles: []
        contactGroups: []
        locale: 'en-us'
      }
      Actual80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: [
          budgetContactEmail
        ]
        contactRoles: []
        contactGroups: []
        locale: 'en-us'
      }
      Forecast80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Forecasted'
        contactEmails: [
          budgetContactEmail
        ]
        contactRoles: []
        contactGroups: []
        locale: 'en-us'
      }
      Actual100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: [
          budgetContactEmail
        ]
        contactRoles: []
        contactGroups: []
        locale: 'en-us'
      }
    }
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: 'azvn${resourceToken}'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/24'
      ]
    }
  }
}

resource containerAppsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: 'azsca${resourceToken}'
  parent: virtualNetwork
  properties: {
    addressPrefix: '10.42.0.0/26'
    delegations: [
      {
        name: 'container-apps-environment'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  name: 'azspe${resourceToken}'
  parent: virtualNetwork
  properties: {
    addressPrefix: '10.42.0.64/27'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  dependsOn: [
    containerAppsSubnet
  ]
}

resource foundryPrivateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for zoneName in foundryPrivateDnsZoneNames: {
    name: zoneName
    location: 'global'
    tags: commonTags
  }
]

resource foundryPrivateDnsVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (zoneName, index) in foundryPrivateDnsZoneNames: {
    name: 'azlnf${resourceToken}'
    parent: foundryPrivateDnsZones[index]
    location: 'global'
    tags: commonTags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: virtualNetwork.id
      }
    }
  }
]

resource cosmosPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: commonTags
}

resource cosmosPrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'azlnc${resourceToken}'
  parent: cosmosPrivateDnsZone
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'azid${resourceToken}'
  location: location
  tags: commonTags
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'azcr${resourceToken}'
  location: location
  tags: commonTags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentity.id, acrPullRoleDefinitionId)
  scope: containerRegistry
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'azlog${resourceToken}'
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

module observability 'observability.bicep' = {
  name: 'clinical-trial-chat-observability'
  params: {
    environmentName: environmentName
    location: location
    logAnalyticsWorkspaceName: logAnalytics.name
    managedIdentityName: managedIdentity.name
    alertEmailAddress: budgetContactEmail
  }
}

resource staticWebApp 'Microsoft.Web/staticSites@2025-03-01' = {
  name: 'azswa${resourceToken}'
  location: location
  tags: union(commonTags, {
    'azd-service-name': 'web'
  })
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {}
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: 'azenv${resourceToken}'
  location: location
  tags: commonTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnet.id
      internal: false
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'azai${resourceToken}'
  location: location
  tags: commonTags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: 'azai${resourceToken}'
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  name: 'azprj${resourceToken}'
  parent: foundry
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Clinical Trial Chatbot'
    description: 'Simple Microsoft Foundry demo with per-user conversation memory.'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  name: modelDeploymentName
  parent: foundry
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-chat-latest'
      version: '2026-08-06'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource appFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, managedIdentity.id, openAiUserRoleDefinitionId)
  scope: foundry
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAiUserRoleDefinitionId
  }
}

resource developerFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(foundry.id, principalId, openAiUserRoleDefinitionId)
  scope: foundry
  properties: {
    principalId: principalId
    principalType: 'User'
    roleDefinitionId: openAiUserRoleDefinitionId
  }
}

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'azpef${resourceToken}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'foundry-account'
        properties: {
          privateLinkServiceId: foundry.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
  dependsOn: [
    foundryProject
    modelDeployment
  ]
}

resource foundryPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  name: 'default'
  parent: foundryPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      for (zoneName, index) in foundryPrivateDnsZoneNames: {
        name: 'foundry-${index}'
        properties: {
          privateDnsZoneId: foundryPrivateDnsZones[index].id
        }
      }
    ]
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2025-04-15' = {
  name: 'azcos${resourceToken}'
  location: location
  tags: commonTags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    disableLocalAuth: true
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: 'Disabled'
    networkAclBypass: 'None'
    isVirtualNetworkFilterEnabled: false
    ipRules: []
    virtualNetworkRules: []
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2025-04-15' = {
  name: cosmosDatabaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
    options: {}
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2025-04-15' = {
  name: cosmosContainerName
  parent: cosmosDatabase
  properties: {
    resource: {
      id: cosmosContainerName
      defaultTtl: memoryRetentionSeconds
      partitionKey: {
        paths: [
          '/userId'
        ]
        kind: 'Hash'
        version: 2
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/content/?'
          }
        ]
      }
    }
    options: {}
  }
}

resource appCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-04-15' = {
  name: guid(cosmosAccount.id, managedIdentity.id, cosmosDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    scope: cosmosAccount.id
  }
}

resource developerCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-04-15' = if (!empty(principalId)) {
  name: guid(cosmosAccount.id, principalId, cosmosDataContributorRoleId)
  parent: cosmosAccount
  properties: {
    principalId: principalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    scope: cosmosAccount.id
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'azpec${resourceToken}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmos-nosql'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource cosmosPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  name: 'default'
  parent: cosmosPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos-nosql'
        properties: {
          privateDnsZoneId: cosmosPrivateDnsZone.id
        }
      }
    ]
  }
}

resource containerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: 'azapp${resourceToken}'
  location: location
  tags: union(commonTags, {
    'azd-service-name': 'chat'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: [
            'https://${staticWebApp.properties.defaultHostname}'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'DELETE'
            'OPTIONS'
          ]
          allowedHeaders: [
            'content-type'
          ]
          allowCredentials: false
          maxAge: 600
        }
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: managedIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'chat'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: 'https://${foundry.name}.openai.azure.com/'
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: modelDeployment.name
            }
            {
              name: 'COSMOS_ENDPOINT'
              value: cosmosAccount.properties.documentEndpoint
            }
            {
              name: 'COSMOS_DATABASE'
              value: cosmosDatabase.name
            }
            {
              name: 'COSMOS_CONTAINER'
              value: cosmosContainer.name
            }
            {
              name: 'Foundry__MaxOutputTokens'
              value: '600'
            }
            {
              name: 'Frontend__AllowedOrigins__0'
              value: 'https://${staticWebApp.properties.defaultHostname}'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: observability.outputs.appInsightsConnectionString
            }
            {
              name: 'OTEL_SERVICE_NAME'
              value: 'clinical-trial-chat-api'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '20'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    acrPullRole
    appFoundryRole
    appCosmosRole
    foundryPrivateDnsZoneGroup
    cosmosPrivateDnsZoneGroup
  ]
}

module foundryHealthProbe 'foundry-health-probe.bicep' = {
  name: 'foundry-health-probe'
  params: {
    environmentName: environmentName
    location: location
    containerRegistryName: containerRegistry.name
    containerEnvironmentName: containerEnvironment.name
    foundryAccountName: foundry.name
    modelDeploymentName: modelDeployment.name
  }
  dependsOn: [
    foundryPrivateDnsZoneGroup
  ]
}

resource staticWebAppBackend 'Microsoft.Web/staticSites/linkedBackends@2025-03-01' = {
  name: uniqueString(containerApp.id)
  parent: staticWebApp
  properties: {
    backendResourceId: containerApp.id
    region: location
  }
}

output containerAppName string = containerApp.name
output probeJobName string = foundryHealthProbe.outputs.jobName
output apiUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output applicationUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output staticWebAppName string = staticWebApp.name
output containerRegistryEndpoint string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
output virtualNetworkName string = virtualNetwork.name
output foundryEndpoint string = 'https://${foundry.name}.openai.azure.com/'
output modelDeploymentName string = modelDeployment.name
output foundryProjectName string = foundryProject.name
output foundryPrivateEndpointName string = foundryPrivateEndpoint.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosDatabaseName string = cosmosDatabase.name
output cosmosContainerName string = cosmosContainer.name
output cosmosPrivateEndpointName string = cosmosPrivateEndpoint.name
output appInsightsConnectionString string = observability.outputs.appInsightsConnectionString
output appInsightsName string = observability.outputs.appInsightsName
output appInsightsResourceId string = observability.outputs.appInsightsResourceId
output healthActionGroupName string = observability.outputs.actionGroupName
output healthActionGroupResourceId string = observability.outputs.actionGroupResourceId
output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceResourceId string = logAnalytics.id
