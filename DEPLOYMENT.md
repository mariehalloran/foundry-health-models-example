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

The tests cover user ID validation, bounded conversation context, frontend entry points, local CORS, starter questions, local chat memory, and deletion.

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
- Azure Cosmos DB serverless account and conversation container.
- A virtual network, private endpoints, and private DNS zones.
- User-assigned managed identity and role assignments.
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

## Deploy application updates

When only application code changed:

```bash
azd deploy
```

Deploy just one service when appropriate:

```bash
azd deploy web
azd deploy chat
```

When Bicep or either service changed:

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

## Cost controls

The default infrastructure uses:

- Container Apps scale-to-zero with at most one replica.
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
