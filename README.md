# Clinical Trial Chatbot on Microsoft Foundry

A small, end-to-end demonstration of a customer-facing clinical trial chatbot built with Microsoft Foundry. The app answers common, non-medical trial questions, remembers each demo user's recent conversations, and stores every interaction in Azure Cosmos DB.

> **Demo only:** This chatbot does not provide medical advice, determine trial eligibility, or replace a study team. Do not enter names, medical record numbers, or other protected health information (PHI).

## What this demonstrates

- A Microsoft Foundry account and project defined with Bicep.
- The latest documented GPT chat model, `gpt-chat-latest` version `2026-08-06`, deployed with the `GlobalStandard` SKU.
- Passwordless access from Azure Container Apps by using managed identity.
- Per-user conversation memory persisted in Azure Cosmos DB.
- A simple ASP.NET Core API and browser chat experience.
- Starter questions that show the intended clinical trial use cases.

`gpt-chat-latest` version `2026-08-06` is a preview model. It is used because this project intentionally demonstrates the latest chat model. For production or regulated workloads, select an approved generally available model and complete security, privacy, compliance, and clinical review.

## Sample questions

- What is a clinical trial?
- What happens during a screening visit?
- What questions should I ask the study team before joining?
- Can I leave a clinical trial after it starts?
- Who pays for trial-related care?
- What should I do if I experience a side effect?

The sample questions are stored in `src/ClinicalTrialChat.Api/Data/sample-questions.json`, displayed in the UI, and referenced by the assistant's system instructions.

## Architecture

```text
Browser
   |
   v
Azure Container App (ASP.NET Core)
   |                         |
   | managed identity        | managed identity
   v                         v
Microsoft Foundry        Azure Cosmos DB
gpt-chat-latest          users + interactions
   |
   v
Foundry project
```

The browser keeps a random demo user ID in local storage. The API uses that ID as the Cosmos DB partition key, loads a bounded window of recent messages before each model call, and saves both the user's message and the assistant's response. Returning with the same browser demonstrates memory without adding a full identity system.

## Project layout

```text
.
├── azure.yaml
├── infra/
│   ├── main.bicep
│   └── main.parameters.json
├── src/
│   └── ClinicalTrialChat.Api/
│       ├── Data/
│       ├── Models/
│       ├── Services/
│       └── wwwroot/
└── tests/
    └── ClinicalTrialChat.Api.Tests/
```

## Prerequisites

- An Azure subscription with permission to create resources and role assignments.
- Azure Developer CLI (`azd`) and Azure CLI (`az`).
- .NET 8 SDK or later for local development.
- Access and quota for `gpt-chat-latest` version `2026-08-06` in the selected Azure region.
- Docker only if you want to build the container locally.

## Deploy to Azure

Authenticate, choose an environment, provision the infrastructure, and deploy the app:

```bash
azd auth login
az login
azd init
azd up
```

The default location is `eastus2`. Model availability and quota vary by subscription and region. Override the location during environment configuration if necessary:

```bash
azd env set AZURE_LOCATION swedencentral
azd up
```

After deployment, `azd` prints the public application URL.

## Run locally against Azure

Provision the Azure resources first:

```bash
azd auth login
az login
azd provision
```

Export the Bicep outputs shown by `azd env get-values`, then run:

```bash
export AZURE_OPENAI_ENDPOINT="https://<foundry-account>.openai.azure.com/"
export AZURE_OPENAI_DEPLOYMENT="clinical-trial-chat"
export COSMOS_ENDPOINT="https://<cosmos-account>.documents.azure.com:443/"
export COSMOS_DATABASE="clinical-trial-chat"
export COSMOS_CONTAINER="interactions"

dotnet run --project src/ClinicalTrialChat.Api
```

Your signed-in Azure identity needs the **Cognitive Services OpenAI User** role on the Foundry account and the **Cosmos DB Built-in Data Contributor** data-plane role on the Cosmos DB account.

Open the URL printed by ASP.NET Core. The same browser remembers its generated demo user ID. Use **Forget me** to delete that user's stored interactions.

## API

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/questions` | Returns the curated starter questions. |
| `GET` | `/api/history/{userId}` | Returns recent messages for one demo user. |
| `POST` | `/api/chat` | Sends a message, calls Foundry, and persists both sides of the exchange. |
| `DELETE` | `/api/history/{userId}` | Deletes the demo user's stored conversation. |
| `GET` | `/health` | Reports whether the web process is running. |

Example chat request:

```json
{
  "userId": "demo-3f4c...",
  "message": "What happens during a screening visit?"
}
```

## Memory and data

Cosmos DB uses `/userId` as the partition key. Each message is a separate document containing:

- `id`
- `userId`
- `role` (`user` or `assistant`)
- `content`
- `createdAt`

Only a bounded number of recent messages is sent to the model. The API validates user IDs and message length, and the UI tells users not to submit PHI. The delete endpoint supports the demo's **Forget me** action.

## Safety boundaries

The system prompt instructs the assistant to:

- Provide general clinical trial education only.
- Never diagnose, recommend treatment, or decide eligibility.
- Direct eligibility and study-specific questions to the study team.
- Direct urgent symptoms to local emergency services.
- Clearly say when information is unknown rather than inventing study details.
- Remind users not to share PHI.

These prompt controls are educational safeguards, not a substitute for production content filtering, identity, authorization, auditing, legal review, or clinical governance.

## Clean up

Delete the Azure resources when finished:

```bash
azd down --purge
```

## Cost notes

This demo creates billable Azure resources, including a model deployment, Azure Container Apps, Azure Container Registry, and Azure Cosmos DB. Cosmos DB is configured for serverless usage and the container app can scale to zero, but model and registry charges may still apply.

