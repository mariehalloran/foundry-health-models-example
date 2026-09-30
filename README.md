# Azure Health Models for Microsoft Foundry

This repository is a reference implementation for monitoring a Microsoft Foundry chat workload with Azure Monitor Health Models. It combines gated Foundry platform availability, Application Insights, and Log Analytics into one workload-level health view.

The goal is to provide a reusable pattern for building a reliable Foundry health model, not to prescribe universal thresholds. Reuse the signal relationships and tune their traffic floors, SLOs, and evaluation windows for your workload.

**Live application:** [Clinical Trial Chat](https://ambitious-glacier-0cabb320f.7.azurestaticapps.net/)

Validate signal behavior and tune every threshold before using the model in production.

## Core reliability pattern: gate availability with `BestOf`

`AzureOpenAIAvailabilityRate` already represents server errors relative to request volume, but a percentage based on one or two requests is too noisy for health. This model combines it with an `AzureOpenAIRequests` minimum-volume gate:

1. Availability evaluates as Healthy, Degraded, or Unhealthy.
2. The request gate is intentionally **Healthy below** the minimum and **Unhealthy at or above** the minimum.
3. Both signals are members of a `BestOf` group, so grouped health is nonhealthy only when both members are nonhealthy.

| Five-minute requests | Request gate | Availability | `BestOf` result |
| ---: | --- | --- | --- |
| Below 20 | Healthy | Any populated state | Healthy |
| At least 20 | Unhealthy | Healthy | Healthy |
| At least 20 | Unhealthy | Degraded | Degraded |
| At least 20 | Unhealthy | Unhealthy | Unhealthy |

`BestOf` selects the healthier member state. Below the traffic floor, the Healthy gate keeps the group Healthy. Once traffic reaches the floor, the Unhealthy gate stops masking availability, so the group preserves availability's Healthy, Degraded, or Unhealthy state. This produces state-level **AND** behavior: enough traffic **and** bad availability.

When adapting the pattern:

- Set the traffic floor above probes, background jobs, and other non-user traffic.
- Keep both signals in the same group; ungrouped members affect entity health independently.
- Derive Degraded and Unhealthy availability thresholds from service objectives.
- Keep anomaly-only metrics on a separate `Suppressed` diagnostics entity.
- For KQL, reproduce the same semantics by returning Healthy below the traffic floor, then evaluating the error-rate thresholds.

## Sample Azure Health Model signals

The model configures 14 evaluated signals across Availability and Diagnostics branches.

The application and runtime thresholds are intentionally sensitive for demonstration purposes. Foundry platform availability is gated by a minimum request floor so low-volume percentages don't create false health transitions. None of the starter thresholds are universal production SLO recommendations. Tune them for expected traffic, dependency behavior, telemetry ingestion delay, and operational response practices.

The Log Analytics reliability query uses a completed, delayed five-minute window so late telemetry and isolated failures don't create health-state flapping.

| Entity | Technical signals | Purpose | Rollup |
| --- | --- | --- | --- |
| Foundry Availability - Azure Metrics | `AzureOpenAIAvailabilityRate`, `AzureOpenAIRequests` | Service-side availability gated by request volume | Foundry Availability, Sev2/Sev1 |
| Foundry Availability - Application OTEL | `foundry.availability_rate`, `foundry.requests` | Client-observed availability with the same gate | Foundry Availability, Sev2/Sev1 |
| Diagnostics - Azure Metrics | `TokenTransaction`, `AzureOpenAINormalizedTBTInMS`, `GeneratedTokens`, `AzureOpenAITTLTInMS`, `AzureOpenAINormalizedTTFTInMS`, `ProcessedPromptTokens`, `RAIRejectedRequests`, `RAIHarmfulRequests`, `RAISystemEvent`, `RAITotalRequests` | Remaining usable platform anomaly signals | Foundry Diagnostics, suppressed, Sev3 |

The platform availability pair is configured in [`infra/health-model-foundry-signals.bicep`](infra/health-model-foundry-signals.bicep). The Availability and Diagnostics parents, Application OTEL availability entity, and Azure Metrics diagnostics entity are configured in [`infra/health-model-observability.bicep`](infra/health-model-observability.bicep).

### Why AzureOpenAIAvailabilityRate is gated

This sample never uses `AzureOpenAIAvailabilityRate` as an ungrouped Health Model signal. The metric is calculated as:

```text
(Total Calls - Server Errors) / Total Calls
```

Server errors include Foundry responses with HTTP status codes of 500 or greater. When no requests reach Foundry during an evaluation window, the metric has no request denominator and can appear as `0%` or no data. Depending on Health Model evaluation behavior, this can make the signal look unhealthy or `Unknown` even though Foundry has not returned an error.

The sample also deploys a scheduled Container Apps Job that sends one direct chat-completion request to Foundry every minute. The platform signals still gate availability with a minimum five-minute request count, so the probe doesn't make low-volume availability authoritative by itself.

Use the gated platform availability group for the account-level reliability view. Treat the probe's execution status as an independent path check rather than relying only on its effect on `AzureOpenAIAvailabilityRate`.

### Synthetic Foundry probe

[`ClinicalTrialChat.Probe`](src/ClinicalTrialChat.Probe) runs in the existing private Container Apps environment with its own least-privilege managed identity. Every minute it calls the configured Foundry deployment with `Reply OK.` and caps the response at 16 completion tokens. Each scheduled execution makes one attempt, has a 45-second application timeout and 55-second job timeout, and isn't retried automatically.

The probe exercises managed identity, private DNS, private endpoint routing, the Foundry gateway, and model inference. It also keeps request metrics active during otherwise idle periods. It is diagnostic traffic, not the Health Model's source of truth:

- Five probe requests per five-minute window remain below the default platform reliability gate of 20 requests.
- Schedule, metric ingestion, and Health Model evaluation boundaries aren't guaranteed to align.
- A startup, identity, DNS, or network failure before the request reaches Foundry doesn't produce a Foundry request metric.
- The job incurs recurring Container Apps execution and model-token charges.

Probe execution failures are visible in Container Apps Job status and console logs. The Health Model continues to rely on the volume-gated availability group.

### Foundry platform metrics

The `Diagnostics - Azure Metrics` entity uses low-sensitivity dynamic thresholds for the remaining platform signals. The Foundry Diagnostics parent is suppressed from root health and owns the Sev3 alert policy.

Dynamic thresholds require representative history before they become useful and should answer "is this unusual?" rather than "is this unacceptable?" New or sparse deployments can remain in their learning period, and slowly evolving behavior might become part of the learned baseline. The Foundry Availability parent owns the Sev2/Sev1 policy for both health sources.

#### Why a diagnostic signal can be `Unknown`

`Unknown` doesn't necessarily mean the signal is broken:

| Signal status | Meaning |
| --- | --- |
| Numeric value, `Unknown`, and no error | The dynamic threshold is still learning that metric series |
| No value, `Unknown`, and no error | The metric produced no sample in the evaluation window or isn't emitted by that deployment |
| `Unknown` with an error | The metric name, query, permissions, or data source configuration failed |

Dynamic thresholds generally need at least three days and 30 samples before they can classify a series, and longer history is required for daily or weekly seasonality. Low sensitivity widens the eventual normal range; it doesn't shorten the learning period. The Diagnostics parent uses `ignoreUnknown: true` and is suppressed from root health, so learning or missing-data intervals don't create availability incidents or Sev3 alerts.

Content-safety metrics remain valuable dashboard and investigation signals, but the sample doesn't use raw safety counts as Health Model state inputs. Blocked content commonly means a guardrail worked as designed, so those counts need a separate safety policy rather than generic health thresholds.

#### Recommended metrics reference

See the official [Azure OpenAI monitoring data reference](https://learn.microsoft.com/en-us/azure/foundry/openai/monitor-openai-reference) for the current recommended metric catalog, supported dimensions, applicability, and export behavior. This example organizes selected metrics by operational intent instead of treating every metric as availability.

### OTEL as an additional datapoint

[`ChatTelemetry`](src/ClinicalTrialChat.Api/Services/ChatTelemetry.cs) defines low-cardinality `foundry.requests` and `foundry.server_errors` counters. [`AzureFoundryChatService`](src/ClinicalTrialChat.Api/Services/AzureFoundryChatService.cs) records them around each logical Foundry operation.

The metrics include no prompt text, response body, user ID, status-code attribute, or other high-cardinality data. They are exported to Application Insights and queried from `AppMetrics`.

Foundry Availability - Application OTEL mirrors the platform availability calculation with client-observed request and server-error counts. Comparing the two availability views helps separate provider behavior from client, identity, network, or application effects.

The deployed application also enables the OpenAI .NET SDK's experimental OpenTelemetry instrumentation for the actual `ChatClient` request. Message-content capture remains disabled.

The Microsoft Foundry tracing article recommends server-side tracing for prompt and hosted agents. This sample is not a hosted agent: it invokes a Foundry model directly through `ChatClient`, so it uses client-side SDK instrumentation instead. The infrastructure connects the existing Application Insights resource to the Foundry project with project-managed-identity authentication and grants the project identity permission to publish telemetry. Direct model traces are available in Application Insights; agent-specific Foundry dashboards still require a Foundry agent or workflow that emits `gen_ai.agent.*` attributes.

For private telemetry ingestion and Health Model query access, see the [AMPLS recommendation for Health Models and OpenTelemetry metrics](docs/ampls-health-model-otel-recommendation.md).

## Health Model structure

```text
Foundry Health Model Example
├── Foundry Availability
│   ├── Foundry Availability - Azure Metrics
│   └── Foundry Availability - Application OTEL
└── Foundry Diagnostics (suppressed)
    └── Diagnostics - Azure Metrics
```

Both branches use `WorstOf` with `ignoreUnknown: true`. Foundry Availability owns the Sev2/Sev1 policy. Foundry Diagnostics owns the Sev3 anomaly policy but is suppressed from root health. Cosmos DB is intentionally not represented in this Health Model.

## Deploy

Prerequisites include an Azure subscription, Azure CLI, Azure Developer CLI, `jq`, Foundry model access, and an existing Azure Monitor Health Model.

```bash
cp deployment.env.example deployment.env
./scripts/configure-azure-context.sh

azd provision --preview
azd up
```

The Health Model templates are separate from the main application deployment so they can also be applied to an existing Foundry workload:

| Template | Purpose |
| --- | --- |
| [`infra/health-model-metrics.bicep`](infra/health-model-metrics.bicep) | Grants the Health Model identity access to Azure metrics and Log Analytics |
| [`infra/health-model-foundry-signals.bicep`](infra/health-model-foundry-signals.bicep) | Adds gated availability/request signals to the existing Foundry entity |
| [`infra/health-model-observability.bicep`](infra/health-model-observability.bicep) | Adds OTEL reliability, both diagnostics entities, relationships, and alerts |
| [`infra/foundry-health-probe.bicep`](infra/foundry-health-probe.bicep) | Runs the one-minute, low-token synthetic Foundry request |
| [`infra/foundry-tracing.bicep`](infra/foundry-tracing.bicep) | Connects Application Insights to Foundry with project-managed-identity ingestion |

See [`DEPLOYMENT.md`](DEPLOYMENT.md) for parameter discovery, preview commands, local development, validation, troubleshooting, and cleanup.

## Validate

```bash
dotnet test ClinicalTrialChat.slnx
```

Always run a Bicep `what-if` or `azd provision --preview` before applying infrastructure changes.

## References

- [Azure OpenAI monitoring data reference](https://learn.microsoft.com/azure/foundry/openai/monitor-openai-reference)
- [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup)
- [Azure Monitor Health Model concepts](https://learn.microsoft.com/azure/azure-monitor/health-models/concepts)
- [Configure signals in Azure Monitor Health Models](https://learn.microsoft.com/azure/azure-monitor/health-models/signals)
- [Azure Container Apps logs](https://learn.microsoft.com/azure/container-apps/log-monitoring)
