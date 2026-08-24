# Foundry Health Model Signal Catalog

This catalog applies the patterns in [abossard/azure-healthmodel-skills](https://github.com/abossard/azure-healthmodel-skills) to this project's Microsoft Foundry account and cross-checks them against the metrics currently exposed by `Microsoft.CognitiveServices/accounts`.

The Health Models API is preview. Validate metric names and behavior again before using this design in production.

## Signal mechanisms

The skills repository defines three query-backed signal kinds:

| Signal kind | Source | Best use |
| --- | --- | --- |
| `AzureResourceMetric` | Native Azure Monitor platform metric | Resource availability, latency, errors, saturation |
| `LogAnalyticsQuery` | KQL against Log Analytics | Ratios, dimension-heavy logic, and zero-guarded derived metrics |
| `PrometheusMetricsQuery` | PromQL against Azure Monitor Workspace | Kubernetes and application Prometheus metrics |

Current `Microsoft.CloudHealth` API `2026-05-01-preview` also supports:

- Built-in Azure Resource Health on an `azureResource` signal group.
- Dependency rollup groups.
- `dimensionFilter` on `AzureResourceMetric`.
- Static comparison operators plus `Dynamic`.
- Optional reusable `signaldefinitions`; entities still contain inline signal bindings.

The skills currently target `2026-01-01-preview`, so use the repository for workflow and design guidance while using the current Microsoft schema for deployable fields.

## Current Foundry metric surface

The deployed AIServices account exposes 88 metric definitions. These are the modern metrics relevant to this chat workload:

### Service health and latency

| Metric | Unit | Logical meaning | Recommendation |
| --- | --- | --- | --- |
| `AzureOpenAIAvailabilityRate` | Percent | `(requests - 5xx) / requests` | Core health |
| `AzureOpenAIRequests` | Count | Request count with deployment and status-code dimensions | Core when filtered |
| `AzureOpenAITTLTInMS` | MilliSeconds | Time to last token/byte for streaming and non-streaming calls | Core health |
| `AzureOpenAITimeToResponse` | MilliSeconds | First response latency, recommended mainly for streaming | Add if the app streams |
| `AzureOpenAINormalizedTTFTInMS` | MilliSeconds | Token-normalized first-token latency | Diagnostic only |
| `AzureOpenAINormalizedTBTInMS` | MilliSeconds | Token generation interval | Diagnostic only |
| `AzureOpenAITokenPerSecond` | Count | Output generation speed | Diagnostic only |

### Usage and cost

| Metric | Logical meaning | Recommendation |
| --- | --- | --- |
| `TokenTransaction` | Prompt plus generated tokens | Usage/cost child entity or dashboard |
| `ProcessedPromptTokens` | Input tokens | Usage/cost child entity or dashboard |
| `GeneratedTokens` | Output tokens | Usage/cost child entity or dashboard |
| `AzureOpenAIContextTokensCacheMatchRate` | Prompt cache efficiency | PTU optimization only |
| `ActiveTokens` | PTU token utilization | Not applicable to Global Standard |
| `AzureOpenAIProvisionedManagedUtilizationV2` | PTU saturation | Not applicable to Global Standard |

### Responsible AI

| Metric | Logical meaning | Recommendation |
| --- | --- | --- |
| `RAIRejectedRequests` | Requests blocked by content filters | Safety child entity or human alert |
| `RAIHarmfulRequests` | Requests detected as harmful | Safety child entity or human alert |
| `RAITotalRequests` | Content-filter request denominator | Use for a derived rate |
| `RAISystemEvent` | Safety system events | Human alert after event types are baselined |

### Duplicate/non-applicable model metrics

`ModelAvailabilityRate`, `ModelRequests`, `TimeToResponse`, `InputTokens`, `OutputTokens`, and `ProvisionedUtilization` are the generic Foundry Models equivalents. For this OpenAI deployment, use the `AzureOpenAI*` metrics to avoid duplicate health signals.

Do not use the legacy Cognitive Services metrics `TotalCalls`, `SuccessfulCalls`, `TotalErrors`, `BlockedCalls`, `ServerErrors`, `ClientErrors`, or `Latency`; their metric descriptions explicitly say not to use them for Azure OpenAI.

## Core Foundry entity signals

The standalone [health-model-foundry-signals.bicep](../infra/health-model-foundry-signals.bicep) template configures two signals by default.

| Signal | Metric and filter | Aggregation/window | Degraded | Unhealthy |
| --- | --- | --- | --- | --- |
| Deployment availability | `AzureOpenAIAvailabilityRate`, deployment filter | Average / 15m | `< 99%` | `< 95%` |
| User-perceived model latency | `AzureOpenAITTLTInMS`, deployment filter | Average / 15m | `> 5,000 ms` | `> 10,000 ms` |

The observed demo baseline at design time was 100% availability with TTLT below one second. The latency thresholds are intentionally conservative and should be revisited after representative load tests.

### Optional sparse error signals

Set `includeSparseErrorSignals=true` only after each filtered status-code series has emitted data. A status code that has never occurred may return no time series and make the signal `Unknown`.

| Signal | Filter | Degraded | Unhealthy |
| --- | --- | --- | --- |
| Server errors | 500, 502, 503, 504 | `> 0 / 15m` | `> 5 / 15m` |
| Throttling | 429 | `> 0 / 5m` | `> 5 / 5m` |
| Client integration errors | 400, 401, 403, 404, 408, 409, 422 | `> 2 / 15m` | `> 10 / 15m` |

These filters use the modern `AzureOpenAIRequests` metric and the `ModelDeploymentName` and `StatusCode` dimensions.

CloudHealth dimension filters don't accept parentheses. Join alternatives for the same dimension with lowercase `or`, then combine the deployment dimension with lowercase `and`.

## Logical/derived metrics

These are useful but cannot be calculated by one native `AzureResourceMetric` signal because they combine multiple series. Implement them as zero-guarded `LogAnalyticsQuery` signals after routing Foundry request and metric diagnostics to Log Analytics.

| Logical metric | Formula | Health placement |
| --- | --- | --- |
| Server error rate | `5xx requests / all requests * 10,000` basis points | Core after traffic is dense enough |
| Throttle rate | `429 requests / all requests * 10,000` basis points | Core saturation |
| Client error rate | selected 4xx / all requests * 10,000 | API integration child or core |
| Safety rejection rate | `RAIRejectedRequests / RAITotalRequests * 10,000` | Limited/suppressed safety child |
| Harmful detection rate | `RAIHarmfulRequests / RAITotalRequests * 10,000` | Limited/suppressed safety child |
| Tokens per request | `TokenTransaction / requests` | Usage/cost child |
| Output-to-input ratio | `GeneratedTokens / ProcessedPromptTokens * 100` | Usage/quality diagnostic |
| Token burn rate | Token total per 5m or 1h | Budget/capacity diagnostic |

Every KQL query should:

1. Return exactly one numeric column.
2. Return zero rather than an empty result when there is no traffic.
3. Use an `ago()` window matching the signal `timeGrain`.
4. Be tested in the target Log Analytics workspace before deployment.

## Entity design

Recommended hierarchy:

```text
Health Model root
└── Foundry service (Standard)
    ├── Foundry inference health (Standard: availability, latency, errors, throttling)
    ├── Foundry safety (Limited or Suppressed: RAI metrics)
    └── Foundry usage (Suppressed: tokens, request volume, cache efficiency)
```

Keep safety and usage signals visible without allowing normal content-filter rejections or token spikes to turn the service entity unhealthy.

## Existing entity corrections

The live Foundry entity was discovered with these issues:

- Availability used `GreaterThan` thresholds, so a healthy value of 100 was evaluated as unhealthy. Availability must use `LessThan`.
- Both `AzureOpenAIAvailabilityRate` and generic `ModelAvailabilityRate` were attached, duplicating availability.
- Legacy `ClientErrors` was attached even though Azure marks it unsupported for Azure OpenAI.

Deploying the standalone signal Bicep performs a full entity update. Signals omitted from the template are removed, so preview it before applying.

Deploy `health-model-foundry-signals.bicep` to the resource group that contains the Health Model. The Foundry account itself can be in another resource group because its full ARM resource ID is a parameter.

## References

- [Health model design skill](https://github.com/abossard/azure-healthmodel-skills/blob/main/skills/healthmodel-design/SKILL.md)
- [Signal catalog skill](https://github.com/abossard/azure-healthmodel-skills/blob/main/skills/healthmodel-signal-catalog/SKILL.md)
- [Azure metrics recipes](https://github.com/abossard/azure-healthmodel-skills/blob/main/skills/healthmodel-signal-catalog/references/metrics.md)
- [PromQL reference](https://github.com/abossard/azure-healthmodel-skills/blob/main/skills/healthmodel-signal-catalog/references/promql-cheatsheet.md)
- [Deployment validation skill](https://github.com/abossard/azure-healthmodel-skills/blob/main/skills/healthmodel-deploy/SKILL.md)
