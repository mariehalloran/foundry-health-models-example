targetScope = 'subscription'

@description('Short name for this deployment environment, such as dev or demo.')
@minLength(1)
@maxLength(32)
param environmentName string

@description('Azure region for the application resources and model deployment.')
param location string = 'eastus2'

@description('Object ID of the person running azd. Leave empty to skip local-development data-plane roles.')
param principalId string = ''

@description('Email address that receives Azure Cost Management budget alerts.')
@minLength(3)
param budgetContactEmail string

@description('Monthly resource-group budget in USD. Azure budgets send alerts; they do not stop resources.')
@minValue(1)
@maxValue(500)
param monthlyBudgetAmount int = 500

@description('Model throughput capacity in thousands of tokens per minute. This limits throughput, not monthly spend.')
@minValue(1)
@maxValue(5)
param modelCapacity int = 2

@description('Number of days that demo conversation messages remain in Cosmos DB.')
@minValue(1)
@maxValue(90)
param memoryRetentionDays int = 30

@description('First day of the budget period. Override only when Cost Management requires a different period.')
param budgetStartDate string = utcNow('yyyy-MM-01T00:00:00Z')

var resourceToken = toLower(uniqueString(subscription().id, location, environmentName))
var resourceGroupName = 'azrg${resourceToken}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
    application: 'clinical-trial-chat'
    'monthly-budget-usd': string(monthlyBudgetAmount)
  }
}

module resources 'resources.bicep' = {
  name: 'clinical-trial-chat-resources'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
    principalId: principalId
    budgetContactEmail: budgetContactEmail
    monthlyBudgetAmount: monthlyBudgetAmount
    modelCapacity: modelCapacity
    memoryRetentionDays: memoryRetentionDays
    budgetStartDate: budgetStartDate
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP_NAME string = resourceGroup.name
output SERVICE_CHAT_RESOURCE_NAME string = resources.outputs.containerAppName
output APPLICATION_URL string = resources.outputs.applicationUrl
output AZURE_OPENAI_ENDPOINT string = resources.outputs.foundryEndpoint
output AZURE_OPENAI_DEPLOYMENT string = resources.outputs.modelDeploymentName
output AZURE_AI_PROJECT_NAME string = resources.outputs.foundryProjectName
output COSMOS_ENDPOINT string = resources.outputs.cosmosEndpoint
output COSMOS_DATABASE string = resources.outputs.cosmosDatabaseName
output COSMOS_CONTAINER string = resources.outputs.cosmosContainerName
