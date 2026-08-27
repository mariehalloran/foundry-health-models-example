# Foundry Health Model Signal Catalog

This catalog applies Azure Monitor Health Model patterns to this project's direct Microsoft Foundry chat-completions workload. The deployable templates configure 10 threshold-based signals plus built-in Azure Resource Health for Foundry. The application isn't a Foundry Agent, so agent-run metrics, continuous-evaluation results, and red-team results aren't used as signal sources.

The Health Models API is preview. Validate metric names and behavior again before using this design in production.

## Signal mechanisms

| Health Model signal type | API representation | Source | Use in this sample |
| --- | --- | --- | --- |
| Azure resource metric | `AzureResourceMetric` | Native Azure Monitor platform metric | Five Foundry metrics |
| Log Analytics workspace | `LogAnalyticsQuery` | KQL against Log Analytics | Five application signals |
| Azure Monitor workspace | `PrometheusMetricsQuery` | PromQL against an Azure Monitor workspace | Not configured |
| Azure Resource Health | `azureResource.resourceHealth` | Azure Resource Health status | Enabled on Foundry |
| External health | `External` and the Health Report Ingestion API | Health evaluated by an application or another monitoring system | Not configured |

The `Microsoft.CloudHealth` API `2026-05-01-preview` also supports:

- Dependency rollup groups.
- Static comparison operators and dynamic thresholds for Azure resource metrics.
- Entity alerts backed by Azure Monitor action groups.

## Relevant Foundry metric surface

### Service health and latency

| Metric | Logical meaning | Recommendation |
| --- | --- | --- |
| `AzureOpenAIAvailabilityRate` | `(requests - 5xx) / requests` | Core health |
| `AzureOpenAIRequests` | Request count with deployment and status-code dimensions | Future KQL-derived rates |
| `AzureOpenAITTLTInMS` | Time to last response byte | Core end-to-end model latency |
| `AzureOpenAITimeToResponse` | First-response latency for streaming requests | Unavailable on Standard deployments |
| `AzureOpenAINormalizedTTFTInMS` | Token-normalized time to first response byte | Prompt-size diagnostic |
| `AzureOpenAINormalizedTBTInMS` | Time between generated tokens | Unavailable on Standard deployments |
| `AzureOpenAITokenPerSecond` | Output generation speed | Unavailable on Standard deployments |

Microsoft's current monitoring reference states that Time to Response, Time Between Tokens, and Tokens per Second aren't available for Standard deployments. This application uses non-streaming chat completions on a Global Standard deployment, so Time to Last Byte (`AzureOpenAITTLTInMS`) is the appropriate model-latency signal. PTU utilization metrics aren't applicable.

### Usage and cost

| Metric | Logical meaning | Recommendation |
| --- | --- | --- |
| `TokenTransaction` | Prompt plus generated inference tokens | Alertable usage signal |
| `ProcessedPromptTokens` | Input tokens | Dashboard and prompt-growth diagnosis |
| `GeneratedTokens` | Output tokens | Dashboard and latency diagnosis |
| `AzureOpenAIContextTokensCacheMatchRate` | Prompt cache efficiency | PTU optimization only |
| `ActiveTokens` | PTU token utilization | Not applicable to Global Standard |
| `AzureOpenAIProvisionedManagedUtilizationV2` | PTU saturation | Not applicable to Global Standard |

Azure recommends pairing latency with token volume. A latency increase accompanied by proportional token growth can be expected, while latency growth without token growth is more likely to indicate a service or network issue.

### Responsible AI

| Metric | Logical meaning | Recommendation |
| --- | --- | --- |
| `RAIRejectedRequests` | Requests blocked by content filters | Foundry health and state alert |
| `RAIHarmfulRequests` | Requests detected as harmful in block or annotate mode | Foundry health and state alert |
| `RAITotalRequests` | Content-filter request denominator | Future derived-rate denominator |
| `RAIAbusiveUsersCount` | Potentially abusive users detected | Security dashboard after baselining |
| `RAISystemEvent` | Safety system events | Human alert after event types are baselined |

Content-filter rejection normally means a guardrail worked, but Health Models evaluate an entity at the worst state of all its signals. These safety signals share the Foundry entity's state alerts. Because the Foundry entity has `Standard` impact and is a child of the workload's `WorstOf` dependency group, safety and usage signals can propagate into workload health; individual signals can't be suppressed from rollup.

### Avoid duplicate or unsupported metrics

`ModelAvailabilityRate`, `ModelRequests`, `TimeToResponse`, `InputTokens`, `OutputTokens`, and `ProvisionedUtilization` are generic Foundry Models equivalents. Use the `AzureOpenAI*` metrics for this OpenAI deployment.

Don't use the legacy Cognitive Services metrics `TotalCalls`, `SuccessfulCalls`, `TotalErrors`, `BlockedCalls`, `ServerErrors`, `ClientErrors`, or `Latency`; their metric descriptions explicitly say not to use them for Azure OpenAI.

## Implemented Foundry signals

The standalone [health-model-foundry-signals.bicep](../infra/health-model-foundry-signals.bicep) template configures five metric signals directly on the existing Foundry entity, enables its built-in Resource Health signal, and adds degraded and unhealthy state alerts. It doesn't create child entities or relationships. All metric signals use a 15-minute time grain and refresh every five minutes.

### Foundry inference

| Signal | Account-level metric | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Foundry availability | `AzureOpenAIAvailabilityRate` | Average / 15m | `< 99%` | `< 95%` |
| Time to last byte | `AzureOpenAITTLTInMS` | Average / 15m | `> 500 ms` | `> 10,000 ms` |

These signals and Azure Resource Health directly determine Foundry entity health.

### Foundry safety

| Signal | Account-level metric | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Harmful requests | `RAIHarmfulRequests` | Total / 15m | `> 0` | `> 5` |
| Content-filter blocks | `RAIRejectedRequests` | Total / 15m | `> 0` | `> 10` |

These signals directly determine Foundry entity health and use the Foundry entity's alert configuration.

### Foundry usage

| Signal | Account-level metric | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Inference-token consumption | `TokenTransaction` | Total / 15m | `> 25,000` | `> 50,000` |

All thresholds in this sample should be tuned after workload baselining. The token thresholds are configurable with `tokenUsageDegradedThreshold` and `tokenUsageUnhealthyThreshold`. This signal directly determines Foundry entity health.

### Dimension-filter compatibility

The deployable signals intentionally aggregate at the Foundry account level. This application provisions one model deployment, so the aggregate represents that deployment unless more deployments are added to the account.

The `2026-05-01-preview` entity schema exposes raw `dimensionFilter` text but no separate `dimension` property. The portal documentation supports selecting a dimension and filter, but raw ARM filter expressions didn't round-trip reliably through the preview editor for this sample and could leave the evaluator in `Unknown`. The template therefore leaves `dimensionFilter` unset.

Status-specific 4xx, 5xx, and 429 platform-metric signals were removed for the same compatibility reason. Availability already captures server-error impact, while the custom OpenTelemetry signal provides an independent application-observed Foundry server-error count without relying on metric dimension filters. Add status-specific rates as zero-guarded KQL signals after exporting `AzureOpenAIRequests` to Log Analytics.

### Synthetic metric population

The base deployment includes a `Microsoft.App/jobs` scheduled job with the cron expression `* * * * *`. It calls the Foundry chat-completions endpoint directly once per minute through the existing private endpoint and private DNS path. The job has no ingress, doesn't use Static Web Apps or the application API, and doesn't access Cosmos DB.

The probe uses a dedicated managed identity with only ACR pull and Cognitive Services OpenAI User assignments. It sends a fixed prompt, allows at most 16 completion tokens, applies a 45-second request timeout, and doesn't retry. This normally contributes about 15 samples to each 15-minute account-level Foundry metric window and prevents an idle workload from being interpreted as a zero availability measurement.

The probe doesn't guarantee a healthy signal. Foundry 5xx responses lower `AzureOpenAIAvailabilityRate` and fail the job execution. Authentication, DNS, image-start, or scheduler failures before Foundry receives the request can still result in missing metric data and an `Unknown` signal. Correlate Foundry signal history with Container Apps Job execution history. The synthetic requests also contribute to latency and token metrics and add about 43,200 model calls per 30-day month.

## Application observability signals

[health-model-observability.bicep](../infra/health-model-observability.bicep) adds five `LogAnalyticsQuery` signals. Each query covers 15 minutes, returns a zero when its source table exists but no matching records are found, and refreshes every five minutes.

| Entity or layer | Signal and source | Degraded | Unhealthy |
| --- | --- | --- | --- |
| Application Insights | API error rate from `AppRequests` | `> 1%` | `> 5%` |
| Application Insights | API P95 duration from `AppRequests` | `> 15,000 ms` | `> 30,000 ms` |
| OpenTelemetry | Foundry HTTP 5xx errors from `foundry.server_errors` in `AppMetrics` | `> 0` | `> 3` |
| Log Analytics | Container runtime errors from `ContainerAppConsoleLogs_CL` | `> 5` | `> 20` |
| Log Analytics | Container ingress 5xx responses from `ContainerAppHTTPLogs` (conditional) | `> 0` | `> 5` |

The application emits the `foundry.server_errors` counter when the OpenAI client surfaces a Foundry response with an HTTP status code of 500 or greater. The metric contains no prompt text, user ID, response body, or other high-cardinality attributes. It intentionally corroborates `AzureOpenAIAvailabilityRate`, whose server-error definition also includes responses with status codes of 500 or greater. The scopes differ: the custom counter covers failures observed by this API and uses count thresholds, while the platform availability rate covers all requests to the Foundry account.

Custom dependency spans are also emitted for Foundry and Cosmos operations. They are diagnostic telemetry only; the current templates don't query those spans as health signals and don't create a Cosmos DB entity. The workload uses `WorstOf` dependency rollup with `ignoreUnknown: true`. The observability template adds workload state alerts; Foundry state alerts come from the Foundry signal template.

The base deployment sends Container Apps console logs to Log Analytics, so `ContainerAppConsoleLogs_CL` is available. It does not enable HTTP diagnostic logs. Microsoft documents that `ContainerAppHTTPLogs` appears only after HTTP logs are enabled with a diagnostic setting on the managed environment, so the ingress 5xx signal remains `Unknown` by default. HTTP records can contain paths, user agents, and client IP information and incur ingestion charges; review privacy and cost requirements before enabling them.

## Entity design

```text
Health Model root
└── Clinical Trial Chat Workload (Standard, workload alerts)
    ├── Microsoft Foundry (Standard, Resource Health, inference, safety, and usage signals)
    ├── Application Insights - API (Standard)
    ├── OpenTelemetry - Foundry (Standard)
    ├── Log Analytics - Runtime (Standard)
    └── Azure Monitor Alerting (Suppressed)
```

A parent entity's state is affected by its children. The workload must therefore parent Foundry and the telemetry layers; Foundry must not parent the workload.

The alerting entity maps the shared action group as a distinct configuration layer. It has no health signal and is suppressed from rollup; alert delivery is driven by alert settings on the workload and Foundry entities.

The templates retain the original relationship resource names while correcting their parent and child properties. This allows incremental deployments to update existing relationships instead of leaving duplicates or a health-propagation cycle.

## Agent-only capabilities deferred

The referenced Foundry monitoring guidance also covers agent run success rate, continuous-evaluation scores, and red-team results. They aren't configured here because this application calls the model directly with `ChatClient` and isn't registered as an agent.

Add them only after one of these changes:

1. Migrate to Foundry Agent Service, or register the application as a custom agent through AI Gateway.
2. Connect the agent and Foundry project to Application Insights.
3. Emit the OpenTelemetry generative-AI semantic conventions required by agent monitoring.
4. Configure the desired recurring evaluations and red-team scans.

For this non-RAG chatbot, relevance and coherence are the most applicable future evaluators. Groundedness and retrieval quality require a retrieval context and aren't meaningful for the current architecture.

## Logical metrics for future use

Implement these as zero-guarded `LogAnalyticsQuery` signals after routing Foundry metrics or evaluation data to Log Analytics:

| Logical metric | Formula | Placement |
| --- | --- | --- |
| Server error rate | `5xx requests / all requests * 10,000` basis points | Inference health |
| Throttle rate | `429 requests / all requests * 10,000` basis points | Inference saturation |
| Client error rate | Selected 4xx / all requests * 10,000 | API integration |
| Safety rejection rate | `RAIRejectedRequests / RAITotalRequests * 10,000` | Safety |
| Harmful detection rate | `RAIHarmfulRequests / RAITotalRequests * 10,000` | Safety |
| Tokens per request | `TokenTransaction / requests` | Usage |
| Output-to-input ratio | `GeneratedTokens / ProcessedPromptTokens * 100` | Usage diagnosis |

Every KQL query should return one record with a selected numeric value column, return zero rather than an empty result, and use an `ago()` window matching the signal time grain.

## Deployment considerations

Deploying [health-model-foundry-signals.bicep](../infra/health-model-foundry-signals.bicep) performs a full update of the existing Foundry entity. Signals omitted from the template are removed, so preview the deployment before applying it. The template doesn't create child entities or relationships.

Deploy [health-model-observability.bicep](../infra/health-model-observability.bicep) after the Foundry signal template. It corrects workload rollup and adds workload-level alerts and application telemetry layers.

## References

- [Monitoring & Observability in Microsoft Foundry](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/monitoring--observability-in-microsoft-foundry/4517250)
- [Azure OpenAI monitoring data reference](https://learn.microsoft.com/azure/foundry/openai/monitor-openai-reference)
- [Monitor agents with the Agent Monitoring Dashboard](https://learn.microsoft.com/azure/foundry/observability/how-to/how-to-monitor-agents-dashboard)
- [Azure Monitor health model concepts](https://learn.microsoft.com/azure/azure-monitor/health-models/concepts)
- [Create and configure signals in Azure Monitor health models](https://learn.microsoft.com/azure/azure-monitor/health-models/signals)
- [Monitor logs in Azure Container Apps with Log Analytics](https://learn.microsoft.com/azure/container-apps/log-monitoring)
