# Local Development and Azure Deployment

This guide covers three ways to run TrialGuide:

| Mode | Model | Memory | Azure required |
| --- | --- | --- | --- |
| Local demo | Canned educational responses | In memory until the process stops | No |
| Deployed app | Microsoft Foundry `gpt-chat-latest` | Azure Cosmos DB | Yes |
| Local app with Azure services | Microsoft Foundry `gpt-chat-latest` | Azure Cosmos DB | Yes, plus private network access |

The local demo is the fastest way to work on the website. Use the deployed app when you need to test the real model, managed identity, private endpoints, and persistent memory.

## Prerequisites

For the local demo:

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- Python 3 or another static-file server for the frontend.

For Azure deployment:

- An Azure subscription where you can create resources and role assignments.
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd).
- Access and quota for `gpt-chat-latest` version `2026-08-06`.

Docker is optional. The project uses Azure Container Registry remote builds by default.

## Run the website locally

Development mode uses:

- In-memory conversation history.
- Canned responses for the standard clinical trial questions.
- No Azure credentials, subscription, VPN, or database.

Start the API from the repository root:

```bash
dotnet restore
dotnet run --project src/ClinicalTrialChat.Api --launch-profile http
```

In a second terminal, serve the separate frontend:

```bash
python3 -m http.server 5173 --directory src/ClinicalTrialChat.Web
```

Open:

```text
http://localhost:5173
```

The frontend calls the local API at `http://localhost:5228`. The page displays **Local demo - canned responses** at the top. Try a starter question, ask what you asked previously, reload the page, and select **Forget me**.

Local memory lasts only while the ASP.NET Core process is running. Stop both processes with `Ctrl+C`.

### Run the local demo in Docker

```bash
docker build \
  --tag clinical-trial-chat:local \
  src/ClinicalTrialChat.Api

docker run --rm \
  --publish 5228:8080 \
  --env LocalDemo__Enabled=true \
  --env Frontend__AllowedOrigins__0=http://localhost:5173 \
  clinical-trial-chat:local

python3 -m http.server 5173 --directory src/ClinicalTrialChat.Web
```

Open `http://localhost:5173`.

## Run automated tests

```bash
dotnet test ClinicalTrialChat.slnx
```

The tests cover user ID validation, bounded conversation context, frontend entry points, local CORS, starter questions, and local chat memory and deletion.

## Configure an Azure environment

Copy the public example to an ignored local file:

```bash
cp deployment.env.example deployment.env
```

Edit `deployment.env`:

```dotenv
AZURE_ENV_NAME=clinical-trial-demo
AZURE_TENANT_ID=<your-tenant-guid>
AZURE_SUBSCRIPTION_ID=<your-subscription-guid>
AZURE_LOCATION=eastus2
AZURE_PRINCIPAL_ID=<optional-user-object-guid>
BUDGET_CONTACT_EMAIL=you@example.com
```

`deployment.env` is ignored by Git. Do not put personal tenant IDs, subscription IDs, or email addresses in `deployment.env.example`, Bicep, or source code.

`AZURE_PRINCIPAL_ID` is optional. Set it to your user object ID when you want the Bicep deployment to assign your account the Foundry and Cosmos DB data-plane roles needed for full local-with-Azure testing.

`BUDGET_CONTACT_EMAIL` receives both Cost Management budget notifications and Health Model alerts.

Authenticate and copy these values into the local `azd` environment:

```bash
./scripts/configure-azure-context.sh
```

The script:

1. Authenticates `az` and `azd` against the configured tenant.
2. Selects and verifies the configured subscription.
3. Creates or selects the named `azd` environment.
4. Stores the settings under the ignored `.azure/` folder.

## Preview and deploy to Azure

Always preview infrastructure changes first:

```bash
azd provision --preview
```

Review the create, modify, and delete operations. Then provision the resources, build the image remotely in Azure Container Registry, and deploy it:

```bash
azd up
```

The deployment creates:

- Microsoft Foundry account and project.
- `gpt-chat-latest` model deployment.
- Standard Azure Static Web App hosting the separate frontend.
- Static Web Apps linked backend that proxies `/api/*` to Container Apps.
- Azure Container App and Container Apps environment.
- Scheduled Container Apps Job that probes Foundry once per minute.
- Azure Cosmos DB serverless account and conversation container.
- A virtual network, private endpoints, and private DNS zones.
- An application managed identity with scoped role assignments.
- Basic Azure Container Registry.
- Log Analytics workspace.
- A monthly Azure budget with alert notifications.

Foundry and Cosmos DB have public network access and local-key authentication disabled. The Container App reaches both services through private endpoints. Static Web Apps linking configures the Container App to accept requests proxied through the Static Web App rather than direct anonymous browser traffic.

## Test the deployed app

Get the URL:

```bash
app_url="$(azd env get-value APPLICATION_URL)"
echo "$app_url"
```

Open the URL in a browser:

1. Select **What happens during a screening visit?**
2. Ask **What visit did I ask about?**
3. Reload and confirm the conversation returns from Cosmos DB.
4. Select **Forget me** and confirm the history disappears.

The Container App can scale to zero. The first request after an idle period can take up to a minute.

Run API smoke tests:

```bash
curl --fail "$app_url/api/health"
curl --fail "$app_url/api/questions"

user_id="demo-$(uuidgen | tr '[:upper:]' '[:lower:]')"

curl --fail \
  --header "Content-Type: application/json" \
  --data "{\"userId\":\"$user_id\",\"message\":\"What is a clinical trial?\"}" \
  "$app_url/api/chat"

curl --fail "$app_url/api/history/$user_id"
curl --fail --request DELETE "$app_url/api/history/$user_id"
```

## Verify the scheduled Foundry probe

The `probe` service deploys a scheduled Container Apps Job into the same private environment as the API. It runs every minute, uses a dedicated managed identity, sends the prompt `Reply OK.`, and allows at most 16 completion tokens.

Inspect the deployed schedule:

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
probe_job_name="$(azd env get-value SERVICE_PROBE_RESOURCE_NAME)"

az containerapp job show \
  --resource-group "$resource_group" \
  --name "$probe_job_name" \
  --query '{
    trigger: properties.configuration.triggerType,
    cron: properties.configuration.scheduleTriggerConfig.cronExpression,
    timeout: properties.configuration.replicaTimeout,
    retries: properties.configuration.replicaRetryLimit
  }'
```

Confirm recent executions are succeeding:

```bash
az containerapp job execution list \
  --resource-group "$resource_group" \
  --name "$probe_job_name" \
  --query '[0:10].{name:name,status:properties.status,start:properties.startTime,end:properties.endTime}' \
  --output table

az containerapp job logs show \
  --resource-group "$resource_group" \
  --name "$probe_job_name" \
  --container probe \
  --tail 20 \
  --format text
```

Each scheduled execution makes one Foundry request with no automatic retry. The application timeout is 45 seconds and the job timeout is 55 seconds. Five probe requests per five-minute window remain below the default platform reliability gate of 20 requests, so probe traffic alone doesn't make `AzureOpenAIAvailabilityRate` health-affecting.

## Deploy application updates

When only application code changed:

```bash
azd deploy
```

Deploy just one service when appropriate:

```bash
azd deploy web
azd deploy chat
azd deploy probe
```

When Bicep or multiple services changed:

```bash
azd provision --preview
azd up
```

Use `azd up`, rather than `azd provision` alone, for normal releases so the application image is deployed after infrastructure reconciliation.

## Run locally against the private Azure services

This is an advanced option. The deployed Foundry and Cosmos DB endpoints reject public traffic, so valid Azure credentials alone are not enough.

Your computer needs:

- A private route to the deployed virtual network, such as point-to-site VPN or a peered development network.
- A DNS resolver that can resolve the linked Foundry and Cosmos DB private DNS zones.
- The Foundry and Cosmos DB data-plane roles, normally assigned through `AZURE_PRINCIPAL_ID`.

After private connectivity is working:

```bash
az login --tenant "$(azd env get-value AZURE_TENANT_ID)"
az account set --subscription "$(azd env get-value AZURE_SUBSCRIPTION_ID)"

export AZURE_OPENAI_ENDPOINT="$(azd env get-value AZURE_OPENAI_ENDPOINT)"
export AZURE_OPENAI_DEPLOYMENT="$(azd env get-value AZURE_OPENAI_DEPLOYMENT)"
export COSMOS_ENDPOINT="$(azd env get-value COSMOS_ENDPOINT)"
export COSMOS_DATABASE="$(azd env get-value COSMOS_DATABASE)"
export COSMOS_CONTAINER="$(azd env get-value COSMOS_CONTAINER)"

ASPNETCORE_ENVIRONMENT=Production \
  dotnet run \
  --project src/ClinicalTrialChat.Api \
  --no-launch-profile \
  --urls http://localhost:5228
```

In a second terminal:

```bash
python3 -m http.server 5173 --directory src/ClinicalTrialChat.Web
```

Open `http://localhost:5173`. The page should display **Microsoft Foundry demo**, not the local canned-response label.

## View logs

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
container_app="$(azd env get-value SERVICE_CHAT_RESOURCE_NAME)"

az containerapp logs show \
  --resource-group "$resource_group" \
  --name "$container_app" \
  --type console \
  --tail 100 \
  --format text
```

## Enable Foundry client tracing

The main `azd` deployment enables OpenAI .NET SDK instrumentation on the Container App and invokes [`infra/foundry-tracing.bicep`](infra/foundry-tracing.bicep). That module connects Application Insights to the Foundry project with `ProjectManagedIdentity` authentication and grants the project identity the **Monitoring Metrics Publisher** role.

To deploy only the tracing connection:

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
foundry_project_name="$(azd env get-value AZURE_AI_PROJECT_NAME)"
app_insights_name="$(azd env get-value APPLICATIONINSIGHTS_NAME)"
foundry_account_name="$(
  az resource list \
    --resource-group "$resource_group" \
    --resource-type Microsoft.CognitiveServices/accounts \
    --query '[0].name' \
    --output tsv
)"

az deployment group what-if \
  --resource-group "$resource_group" \
  --template-file infra/foundry-tracing.bicep \
  --parameters \
    foundryAccountName="$foundry_account_name" \
    foundryProjectName="$foundry_project_name" \
    appInsightsName="$app_insights_name"

az deployment group create \
  --name foundry-tracing \
  --resource-group "$resource_group" \
  --template-file infra/foundry-tracing.bicep \
  --parameters \
    foundryAccountName="$foundry_account_name" \
    foundryProjectName="$foundry_project_name" \
    appInsightsName="$app_insights_name"
```

When deploying without a full `azd up`, enable the runtime feature flag and deploy the chat service:

```bash
container_app_name="$(azd env get-value SERVICE_CHAT_RESOURCE_NAME)"

az containerapp update \
  --resource-group "$resource_group" \
  --name "$container_app_name" \
  --set-env-vars \
    OPENAI_EXPERIMENTAL_ENABLE_OPEN_TELEMETRY=true \
    OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=false

azd deploy chat
```

## Verify Foundry client tracing

The deployed chat application enables the OpenAI .NET SDK's experimental OpenTelemetry instrumentation and exports the `OpenAI.ChatClient` source and meter to Application Insights. Prompt and response content are not captured.

Send a chat request, wait several minutes for ingestion, and query the workspace:

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
workspace_name="$(azd env get-value LOG_ANALYTICS_WORKSPACE_NAME)"
workspace_customer_id="$(
  az monitor log-analytics workspace show \
    --resource-group "$resource_group" \
    --workspace-name "$workspace_name" \
    --query customerId \
    --output tsv
)"

az monitor log-analytics query \
  --workspace "$workspace_customer_id" \
  --analytics-query '
    AppDependencies
    | where TimeGenerated > ago(30m)
    | where AppRoleName endswith "clinical-trial-chat-api"
    | where Name startswith "chat "
    | project TimeGenerated, Name, Target, Success, DurationMs, Properties
    | order by TimeGenerated desc
  ' \
  --output table
```

The Foundry project is connected to the same Application Insights resource with project-managed-identity authentication. Because this application calls `ChatClient` directly rather than running a Foundry agent, use Application Insights to inspect these client spans. Agent-specific views require a Foundry agent or workflow that emits `gen_ai.agent.*` attributes.

## Grant an Azure Health Model access to metrics

Azure platform metrics are collected automatically and do not require diagnostic settings. A `Microsoft.CloudHealth/healthmodels` resource reads those metrics through its managed identity, which needs Azure RBAC access to the monitored resources.

The standalone [`infra/health-model-metrics.bicep`](infra/health-model-metrics.bicep) template grants the existing health model identity the **Monitoring Reader** role on one resource group. It is intentionally separate from the main application Bicep deployment.

Preview the role assignment:

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
log_analytics_workspace_name="$(azd env get-value LOG_ANALYTICS_WORKSPACE_NAME)"

az deployment group what-if \
  --resource-group "$resource_group" \
  --template-file infra/health-model-metrics.bicep \
  --parameters \
    healthModelName="<your-health-model-name>" \
    healthModelResourceGroupName="<health-model-resource-group>" \
    logAnalyticsWorkspaceName="$log_analytics_workspace_name"
```

Apply it:

```bash
az deployment group create \
  --name health-model-metrics-access \
  --resource-group "$resource_group" \
  --template-file infra/health-model-metrics.bicep \
  --parameters \
    healthModelName="<your-health-model-name>" \
    healthModelResourceGroupName="<health-model-resource-group>" \
    logAnalyticsWorkspaceName="$log_analytics_workspace_name"
```

The deployment scope is the resource group whose metrics the health model must read. Repeat the deployment for each additional monitored resource group. RBAC changes can take several minutes to propagate before the Health Model UI can read metrics.

### Configure the Foundry entity signals

Review the [available Azure Health Model signals](README.md#available-azure-health-model-signals) before applying the signal template. The signal template performs a full update of the existing Foundry entity, so signals not declared in the template are removed. It doesn't create any additional Health Model entities or relationships.

Discover the required values without hardcoding resource IDs:

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
health_model_name="$(
  az resource list \
    --resource-group "$resource_group" \
    --resource-type Microsoft.CloudHealth/healthmodels \
    --query '[0].name' \
    --output tsv
)"
foundry_resource_id="$(
  az resource list \
    --resource-group "$resource_group" \
    --resource-type Microsoft.CognitiveServices/accounts \
    --query '[0].id' \
    --output tsv
)"
health_model_resource_id="$(
  az resource show \
    --resource-group "$resource_group" \
    --resource-type Microsoft.CloudHealth/healthmodels \
    --name "$health_model_name" \
    --api-version 2026-05-01-preview \
    --query id \
    --output tsv
)"
foundry_entity_name="$(
  az rest \
    --method get \
    --url "https://management.azure.com${health_model_resource_id}/entities?api-version=2026-05-01-preview" \
  | jq -r --arg id "$foundry_resource_id" \
      '.value[] | select(.properties.signalGroups.azureResource.azureResourceId == $id) | .name'
)"
action_group_resource_id="$(azd env get-value AZURE_MONITOR_ACTION_GROUP_ID)"
```

Preview the gated Foundry platform reliability signals:

```bash
az deployment group what-if \
  --resource-group "$resource_group" \
  --template-file infra/health-model-foundry-signals.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    foundryResourceId="$foundry_resource_id" \
    foundryPlatformMinimumRequests=20 \
    foundryPlatformDegradedAvailabilityPercent=99 \
    foundryPlatformUnhealthyAvailabilityPercent=95 \
    actionGroupResourceId="$action_group_resource_id"
```

Apply only after reviewing the entity replacement:

```bash
az deployment group create \
  --name foundry-health-signals \
  --resource-group "$resource_group" \
  --template-file infra/health-model-foundry-signals.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    foundryResourceId="$foundry_resource_id" \
    foundryPlatformMinimumRequests=20 \
    foundryPlatformDegradedAvailabilityPercent=99 \
    foundryPlatformUnhealthyAvailabilityPercent=95 \
    actionGroupResourceId="$action_group_resource_id"
```

The Foundry Availability - Azure Metrics entity contains `AzureOpenAIAvailabilityRate` and `AzureOpenAIRequests`. Availability is never ungrouped: the minimum-request signal is intentionally Unhealthy when the gate is open, and a `BestOf` group preserves the availability state only when traffic is sufficient.

| Five-minute requests | Availability | Group state |
| --- | --- | --- |
| Below minimum | Any populated value | Healthy |
| At or above minimum | Healthy | Healthy |
| At or above minimum | Degraded | Degraded |
| At or above minimum | Unhealthy | Unhealthy |

The one-minute synthetic probe keeps the path exercised and usually keeps request metrics populated, but its five requests per five-minute window remain below the default gate of 20. At zero traffic the platform metrics can be `Unknown` without generating a threshold alert.

### Configure availability and diagnostics

Deploy the observability template after the Foundry signal template. It creates a Foundry Availability branch with Azure Metrics and Application OTEL children and a suppressed Foundry Diagnostics branch containing the remaining Azure metrics.

Foundry Availability - Application OTEL uses two KQL signals over a completed five-minute window: an availability percentage derived from `foundry.server_errors` and `foundry.requests`, and a request-count gate. A `BestOf` group combines them with the same 20-request, 99%, and 95% settings as the Azure Metrics pair.

Diagnostics - Azure Metrics uses native low-sensitivity dynamic thresholds and propagates only to the suppressed Foundry Diagnostics parent, which owns the Sev3 alert policy.

Newly configured dynamic signals can remain `Unknown` while Azure learns their normal behavior. A numeric value with no error means collection is working and the baseline isn't ready. A null value with no error means no sample was emitted in the window. An `error` field indicates an actual configuration, permission, query, or unsupported-metric problem. The Diagnostics parent ignores unknown children and is suppressed from root health, so only evaluated anomalies generate Sev3 alerts.

```bash
log_analytics_workspace_id="$(azd env get-value LOG_ANALYTICS_WORKSPACE_ID)"
```

Preview the OTEL reliability and diagnostics signals:

```bash
az deployment group what-if \
  --resource-group "$resource_group" \
  --template-file infra/health-model-observability.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    foundryResourceId="$foundry_resource_id" \
    logAnalyticsWorkspaceResourceId="$log_analytics_workspace_id" \
    otelReliabilityMinimumRequests=20 \
    otelDegradedAvailabilityPercent=99 \
    otelUnhealthyAvailabilityPercent=95 \
    actionGroupResourceId="$action_group_resource_id"
```

Apply after reviewing the relationship corrections. Health Model relationship endpoints are immutable, so remove obsolete or duplicate edges before migrating an existing graph to the stable `health-root-to-*`, `reliability-to-*`, and `diagnostics-to-*` relationship names.

```bash
az deployment group create \
  --name health-model-observability \
  --resource-group "$resource_group" \
  --template-file infra/health-model-observability.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    foundryResourceId="$foundry_resource_id" \
    logAnalyticsWorkspaceResourceId="$log_analytics_workspace_id" \
    otelReliabilityMinimumRequests=20 \
    otelDegradedAvailabilityPercent=99 \
    otelUnhealthyAvailabilityPercent=95 \
    actionGroupResourceId="$action_group_resource_id"
```

The resulting graph places Foundry Availability and suppressed Foundry Diagnostics under the root. Cosmos DB remains part of the application infrastructure but isn't represented in this Health Model.

Resource-group deployments are incremental. When upgrading a graph created by an earlier version of this example, remove the obsolete Cosmos DB relationship once:

```bash
az rest \
  --method delete \
  --url "https://management.azure.com${health_model_resource_id}/relationships/health-root-to-cosmos?api-version=2026-05-01-preview"
```

Deleting the relationship doesn't delete the Cosmos DB account or an existing Cosmos DB entity.

Earlier versions used separate workload, Application Insights, and OpenTelemetry entities. After consolidating the comparison entities under Foundry, remove these obsolete relationships if they exist:

```bash
for relationship_name in \
  health-root-to-foundry \
  foundry-to-diagnostics \
  foundry-to-log-analytics \
  foundry-to-otel-diagnostics \
  health-root-to-token-efficiency \
  token-efficiency-to-metrics \
  token-efficiency-to-otel \
  health-root-to-latency \
  latency-to-metrics \
  latency-to-otel \
  diagnostics-to-otel \
  health-root-to-workload \
  chat-workload-to-log-analytics \
  chat-workload-to-application-insights \
  chat-workload-to-foundry-reliability \
  chat-workload-to-opentelemetry; do
  az rest \
    --method delete \
    --url "https://management.azure.com${health_model_resource_id}/relationships/${relationship_name}?api-version=2026-09-01-preview"
done
```

Then remove the obsolete entities:

```bash
for entity_name in \
  clinical-trial-chat-workload \
  application-insights-api \
  foundry-workload-reliability \
  opentelemetry-dependencies \
  token-efficiency \
  foundry-token-efficiency-metrics \
  foundry-token-efficiency-otel \
  latency \
  foundry-latency-metrics \
  foundry-latency-otel \
  otel-diagnostics; do
  az rest \
    --method delete \
    --url "https://management.azure.com${health_model_resource_id}/entities/${entity_name}?api-version=2026-09-01-preview"
done
```

## Cost controls

The default infrastructure uses:

- Container Apps scale-to-zero with at most one replica.
- A one-minute Container Apps Job probe with one request, no retries, and a 16-token completion cap.
- Standard Static Web Apps, required for the linked Container Apps backend.
- Cosmos DB serverless.
- Basic Container Registry.
- Bounded model capacity and response tokens.
- Thirty-day conversation TTL.
- A 1 GB/day Log Analytics ingestion cap.
- A $500 monthly budget with threshold alerts.

The Standard Static Web Apps plan had a $9/month base retail price in `eastus2` when this guide was updated. Azure budgets send notifications but do not automatically stop resources.

## Delete the Azure environment

When you finish testing:

```bash
azd down --purge
```

Review the confirmation carefully. This permanently deletes the environment's resource group and stored conversation data.
