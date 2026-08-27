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

The tests cover user ID validation, bounded conversation context, frontend entry points, local CORS, starter questions, local chat memory and deletion, plus the direct Foundry probe request and managed-identity token scope.

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
- One-minute scheduled Container Apps Job that calls Foundry directly.
- Azure Cosmos DB serverless account and conversation container.
- A virtual network, private endpoints, and private DNS zones.
- Separate application and probe managed identities with scoped role assignments.
- Basic Azure Container Registry.
- Log Analytics workspace.
- A monthly Azure budget with alert notifications.

Foundry and Cosmos DB have public network access and local-key authentication disabled. The Container App reaches both services through private endpoints. Static Web Apps linking configures the Container App to accept requests proxied through the Static Web App rather than direct anonymous browser traffic.

The scheduled job has no ingress and doesn't call Static Web Apps or the application API. It uses its dedicated managed identity to send one fixed chat-completion request directly to Foundry through the same VNet and private DNS path.

The probe identity, role assignments, and job are isolated in [`infra/foundry-health-probe.bicep`](infra/foundry-health-probe.bicep). The main deployment invokes this module, and operators can also preview or deploy it independently when unrelated resources in the environment have drift.

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

Verify the one-minute probe schedule:

```bash
resource_group="$(azd env get-value AZURE_RESOURCE_GROUP_NAME)"
probe_job="$(azd env get-value SERVICE_PROBE_RESOURCE_NAME)"

az containerapp job execution list \
  --name "$probe_job" \
  --resource-group "$resource_group" \
  --query '[].{Status:properties.status,Name:name,StartTime:properties.startTime}' \
  --output table
```

Wait up to two minutes after deployment if necessary. The latest execution should be `Succeeded`. Each run makes one direct Foundry request with a maximum of 16 completion tokens, no retry, and a 45-second request timeout.

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

View the scheduled probe's latest execution logs:

```bash
probe_job="$(azd env get-value SERVICE_PROBE_RESOURCE_NAME)"

az containerapp job logs show \
  --resource-group "$resource_group" \
  --name "$probe_job" \
  --container probe
```

A successful run logs `Foundry synthetic probe succeeded` with the elapsed request time and Foundry request ID. A failed HTTP response, empty response, or timeout makes the job execution fail.

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

Preview the Foundry inference, safety, and usage signals:

```bash
az deployment group what-if \
  --resource-group "$resource_group" \
  --template-file infra/health-model-foundry-signals.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    foundryResourceId="$foundry_resource_id" \
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
    actionGroupResourceId="$action_group_resource_id"
```

The template intentionally uses account-level Foundry metrics without `dimensionFilter`. This application provisions one model deployment, so the aggregate represents that deployment unless more deployments are added to the account. The `2026-05-01-preview` entity schema exposes raw `dimensionFilter` text but no separate `dimension` property. Although the portal supports structured dimension selection, raw ARM filter expressions didn't round-trip reliably through the preview editor for this sample and could leave signal evaluation in `Unknown`. Keep the filter unset until the API, editor, and evaluator handle the same filter representation reliably.

The scheduled job sends one synthetic request per minute into these same account-level metrics. It keeps low-traffic windows populated but doesn't force the availability signal to healthy: a Foundry 5xx lowers `AzureOpenAIAvailabilityRate`, while a job failure before the request reaches Foundry can still leave missing metric data. Review Container Apps Job execution history when the Foundry signal is `Unknown`.

The Foundry token-usage signal defaults to degraded above 25,000 inference tokens per 15 minutes and unhealthy above 50,000. Override these starter thresholds after baselining:

```bash
--parameters \
  tokenUsageDegradedThreshold=50000 \
  tokenUsageUnhealthyThreshold=100000
```

### Configure workload rollup and application observability

Deploy the layered observability template after the Foundry signal template. It makes the workload depend on Foundry, Application Insights, OpenTelemetry dependencies, and Log Analytics runtime signals. Degraded and unhealthy workload states notify the same action group.

The OpenTelemetry signal counts Foundry HTTP 5xx responses surfaced to the API through the `foundry.server_errors` metric. It intentionally corroborates the account-level `AzureOpenAIAvailabilityRate` signal, although the custom metric covers only application-observed requests and uses count thresholds.

The base deployment sends console logs to Log Analytics but doesn't enable Container Apps HTTP diagnostic logs. The `ContainerAppHTTPLogs`-based ingress 5xx signal remains `Unknown` until HTTP logs are enabled on the managed environment. Review the [HTTP log schema](https://learn.microsoft.com/azure/container-apps/log-monitoring#http-logs), including its path, user-agent, and client-IP fields, and the additional ingestion cost before enabling that diagnostic category.

```bash
container_app_name="$(azd env get-value SERVICE_CHAT_RESOURCE_NAME)"
app_insights_resource_id="$(azd env get-value APPLICATIONINSIGHTS_RESOURCE_ID)"
log_analytics_workspace_id="$(azd env get-value LOG_ANALYTICS_WORKSPACE_ID)"
```

Preview the hierarchy and workload signals:

```bash
az deployment group what-if \
  --resource-group "$resource_group" \
  --template-file infra/health-model-observability.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    containerAppName="$container_app_name" \
    appInsightsResourceId="$app_insights_resource_id" \
    logAnalyticsWorkspaceResourceId="$log_analytics_workspace_id" \
    actionGroupResourceId="$action_group_resource_id"
```

Apply after reviewing the relationship corrections:

```bash
az deployment group create \
  --name health-model-observability \
  --resource-group "$resource_group" \
  --template-file infra/health-model-observability.bicep \
  --parameters \
    healthModelName="$health_model_name" \
    foundryEntityName="$foundry_entity_name" \
    containerAppName="$container_app_name" \
    appInsightsResourceId="$app_insights_resource_id" \
    logAnalyticsWorkspaceResourceId="$log_analytics_workspace_id" \
    actionGroupResourceId="$action_group_resource_id"
```

The template retains the original relationship resource names while reversing their parent and child properties. This is intentional: an incremental deployment updates existing relationships in place instead of leaving duplicate relationships or a rollup cycle.

## Cost controls

The default infrastructure uses:

- Container Apps scale-to-zero with at most one replica.
- A run-to-completion probe with one replica, no retries, and one execution per minute.
- Standard Static Web Apps, required for the linked Container Apps backend.
- Cosmos DB serverless.
- Basic Container Registry.
- Bounded model capacity and response tokens.
- Thirty-day conversation TTL.
- A 1 GB/day Log Analytics ingestion cap.
- A $500 monthly budget with threshold alerts.

The probe runs about 43,200 times per 30-day month. Each run uses Container Apps execution time and a small Foundry request, so include both compute and model-token usage when tuning the budget.

The Standard Static Web Apps plan had a $9/month base retail price in `eastus2` when this guide was updated. Azure budgets send notifications but do not automatically stop resources.

## Delete the Azure environment

When you finish testing:

```bash
azd down --purge
```

Review the confirmation carefully. This permanently deletes the environment's resource group and stored conversation data.
