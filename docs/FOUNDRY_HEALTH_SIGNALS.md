# Foundry Health Model Signal Catalog

This catalog applies Azure Monitor Health Model patterns to this project's direct Microsoft Foundry chat-completions workload. The application isn't a Foundry Agent, so agent-run, continuous-evaluation, and red-team signals aren't included in the deployable templates.

The Health Models API is preview. Validate metric names and behavior again before using this design in production.

## Signal mechanisms

| Signal kind | Source | Best use |
| --- | --- | --- |
| `AzureResourceMetric` | Native Azure Monitor platform metric | Resource availability, latency, errors, safety, and usage |
| `LogAnalyticsQuery` | KQL against Log Analytics | Ratios, percentiles, application telemetry, and zero-guarded derived metrics |
| `PrometheusMetricsQuery` | PromQL against Azure Monitor Workspace | Kubernetes and application Prometheus metrics |

The `Microsoft.CloudHealth` API `2026-05-01-preview` also supports:

- Built-in Azure Resource Health on an `azureResource` signal group.
- Dependency rollup groups.
- `dimensionFilter` on `AzureResourceMetric`.
- Static comparison operators and dynamic thresholds.
- Entity alerts backed by Azure Monitor action groups.

## Relevant Foundry metric surface

### Service health and latency

| Metric | Logical meaning | Recommendation |
| --- | --- | --- |
| `AzureOpenAIAvailabilityRate` | `(requests - 5xx) / requests` | Core health |
| `AzureOpenAIRequests` | Request count with deployment and status-code dimensions | Core when filtered |
| `AzureOpenAITTLTInMS` | Time to last token or byte | Core health |
| `AzureOpenAITimeToResponse` | First response latency | Use for streaming workloads |
| `AzureOpenAINormalizedTTFTInMS` | Token-normalized first-token latency | Diagnostic only |
| `AzureOpenAINormalizedTBTInMS` | Token generation interval | Diagnostic only |
| `AzureOpenAITokenPerSecond` | Output generation speed | Diagnostic only |

This application uses non-streaming chat completions on a Global Standard deployment, so `AzureOpenAITTLTInMS` is the appropriate model-latency signal. PTU utilization metrics aren't applicable.

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
| `RAIRejectedRequests` | Requests blocked by content filters | Safety entity and human alert |
| `RAIHarmfulRequests` | Requests detected as harmful | Safety entity and human alert |
| `RAITotalRequests` | Content-filter request denominator | Future derived-rate denominator |
| `RAIAbusiveUsersCount` | Potentially abusive users detected | Security dashboard after baselining |
| `RAISystemEvent` | Safety system events | Human alert after event types are baselined |

Content-filter rejection normally means a guardrail worked. Safety signals therefore have their own alerts but are suppressed from workload availability rollup.

### Avoid duplicate or unsupported metrics

`ModelAvailabilityRate`, `ModelRequests`, `TimeToResponse`, `InputTokens`, `OutputTokens`, and `ProvisionedUtilization` are generic Foundry Models equivalents. Use the `AzureOpenAI*` metrics for this OpenAI deployment.

Don't use the legacy Cognitive Services metrics `TotalCalls`, `SuccessfulCalls`, `TotalErrors`, `BlockedCalls`, `ServerErrors`, `ClientErrors`, or `Latency`; their metric descriptions explicitly say not to use them for Azure OpenAI.

## Implemented Foundry signals

The standalone [health-model-foundry-signals.bicep](../infra/health-model-foundry-signals.bicep) template configures five signals by default.

### Azure Monitor - Foundry Inference

| Signal | Metric and filter | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Deployment availability | `AzureOpenAIAvailabilityRate`, deployment filter | Average / 15m | `< 99%` | `< 95%` |
| User-perceived model latency | `AzureOpenAITTLTInMS`, deployment filter | Average / 15m | `> 5,000 ms` | `> 10,000 ms` |

The inference entity has standard impact, so its state rolls up through the Foundry account to workload health.

### Foundry Safety

| Signal | Metric and filter | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Harmful requests | `RAIHarmfulRequests`, deployment filter | Total / 15m | `> 0` | `> 5` |
| Content-filter blocks | `RAIRejectedRequests`, deployment filter | Total / 15m | `> 0` | `> 10` |

The safety entity has suppressed impact and emits its own Sev3 degraded and Sev2 unhealthy alerts. This keeps safety events visible without treating successful guardrail enforcement as an availability failure.

### Foundry Usage

| Signal | Metric and filter | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Inference-token consumption | `TokenTransaction`, deployment filter | Total / 15m | `> 25,000` | `> 50,000` |

The thresholds are starter values and are configurable with `tokenUsageDegradedThreshold` and `tokenUsageUnhealthyThreshold`. The usage entity has suppressed impact and emits its own Sev3 and Sev2 alerts.

### Optional sparse error signals

Set `includeSparseErrorSignals=true` only after each filtered status-code series has emitted data. A status code that has never occurred may return no time series and make the signal `Unknown`.

| Signal | Filter | Degraded | Unhealthy |
| --- | --- | --- | --- |
| Server errors | 500, 502, 503, 504 | `> 0 / 15m` | `> 5 / 15m` |
| Throttling | 429 | `> 0 / 5m` | `> 5 / 5m` |
| Client integration errors | 400, 401, 403, 404, 408, 409, 422 | `> 2 / 15m` | `> 10 / 15m` |

These filters use `AzureOpenAIRequests` with `ModelDeploymentName` and `StatusCode` dimensions. Error and throttle rates are preferable once Foundry metrics are exported to Log Analytics and can be queried with a zero guard.

## Application observability signals

[health-model-observability.bicep](../infra/health-model-observability.bicep) adds these nonduplicated workload layers:

| Layer | Signals |
| --- | --- |
| Application Insights | API error rate and P95 request duration |
| OpenTelemetry | Foundry and Cosmos dependency failures |
| Log Analytics | Container runtime errors and ingress 5xx responses |
| Alerting | Suppressed action-group entity plus workload, safety, and usage state alerts |

The application emits custom dependency spans for Foundry and Cosmos operations. These support root-cause diagnosis without duplicating Foundry platform metrics.

## Entity design

```text
Health Model root
└── Clinical Trial Chat Workload (Standard, workload alerts)
    ├── Microsoft Foundry (Standard, Resource Health)
    │   ├── Azure Monitor - Foundry Inference (Standard)
    │   ├── Foundry Safety (Suppressed, dedicated alerts)
    │   └── Foundry Usage (Suppressed, dedicated alerts)
    ├── Application Insights - API (Standard)
    ├── OpenTelemetry Dependencies (Standard)
    ├── Log Analytics - Runtime (Standard)
    └── Azure Monitor Alerting (Suppressed)
```

A parent entity's state is affected by its children. The workload must therefore parent Foundry and the telemetry layers; Foundry must not parent the workload.

The alerting entity maps the shared action group as a distinct configuration layer. It has no health signal and is suppressed from rollup; alert delivery is driven by alert settings on the workload, safety, and usage entities.

The templates retain the original relationship resource names while correcting their parent and child properties. This allows incremental deployments to update existing relationships instead of leaving duplicates or a health-propagation cycle.

## Agent-only capabilities deferred

The referenced Foundry monitoring guidance also recommends agent run success rate, continuous evaluation scores, and red-team results. They aren't configured here because this application calls the model directly with `ChatClient`.

Add them only after one of these changes:

1. Migrate to Foundry Agent Service.
2. Register the application as a custom agent through AI Gateway.
3. Connect the Foundry project to Application Insights and emit the required OpenTelemetry generative-AI semantic conventions.

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

Every KQL query should return exactly one numeric column, return zero rather than an empty result, and use an `ago()` window matching the signal time grain.

## Deployment considerations

Deploying [health-model-foundry-signals.bicep](../infra/health-model-foundry-signals.bicep) performs full updates of the Foundry and named child entities. Signals omitted from the template are removed, so preview the deployment before applying it.

Deploy [health-model-observability.bicep](../infra/health-model-observability.bicep) after the Foundry signal template. It corrects workload rollup and adds workload-level alerts and application telemetry layers.

## References

- [Monitoring & Observability in Microsoft Foundry](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/monitoring--observability-in-microsoft-foundry/4517250)
- [Azure OpenAI monitoring data reference](https://learn.microsoft.com/azure/foundry/openai/monitor-openai-reference)
- [Monitor agents with the Agent Monitoring Dashboard](https://learn.microsoft.com/azure/foundry/observability/how-to/how-to-monitor-agents-dashboard)
- [Azure Monitor health model concepts](https://learn.microsoft.com/azure/azure-monitor/health-models/concepts)
