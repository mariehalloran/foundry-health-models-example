# AMPLS Recommendation for Health Models and OpenTelemetry Metrics

Last reviewed: 2026-09-24

## Purpose

This document recommends a network and identity design for a private Microsoft
Foundry workload that exports OpenTelemetry (OTEL) metrics to Azure Monitor and
uses Azure Monitor Health Models to evaluate those metrics.

The recommendation applies primarily to Foundry telemetry sent to a
workspace-based Application Insights resource and stored in its Log Analytics
workspace. It also describes the alternative Azure Monitor workspace and
Managed Prometheus path.

Validate the behavior in the
target region and API version before enforcing production network restrictions.

## Recommendation

For Foundry OTEL metrics stored in Application Insights:

1. Send telemetry privately from the workload through an Azure Monitor Private
   Link Scope (AMPLS).
2. Add both Application Insights and its backing Log Analytics workspace to the
   AMPLS.
3. Set AMPLS ingestion access to `PrivateOnly` after private ingestion is
   validated.
4. Keep Log Analytics query network access open for the Health Model evaluator,
   while protecting every query with Microsoft Entra authentication and
   least-privilege Azure RBAC.
5. Grant the Health Model managed identity `Monitoring Reader` on the target
   workspace and `Reader` on represented Azure resources.
6. Configure a Log Analytics signal that reads the OTEL metric from
   `AppMetrics` and returns one numeric record.

The recommended access split is:

| Plane | Network setting | Authorization |
| --- | --- | --- |
| Telemetry ingestion | Private through AMPLS | Managed identity; local authentication disabled |
| Health Model query | Open network path | Health Model managed identity with scoped Azure RBAC |

Open query network access does not make telemetry anonymous. Azure Monitor still
requires an authenticated identity with data-plane permission.

If the primary workspace contains raw or sensitive telemetry and must keep
public query access disabled, use the two-workspace alternative described below.
Keep the primary workspace private and expose only a separate, minimized
health-signal workspace to the Health Model evaluator.

## Why query access remains open

AMPLS provides a private route for clients that can reach a private endpoint in
a connected virtual network. The current public Health Models documentation
describes managed-identity authentication but does not document a way to inject
the managed Health Model evaluator into a customer virtual network or attach the
evaluator itself to an AMPLS private endpoint.

Do not assume that creating an AMPLS private endpoint in the Foundry workload
virtual network makes service-side Health Model evaluation use that endpoint.
If public query access is disabled and signal evaluation starts failing, adding
more RBAC roles will not repair the missing network path.

Use this baseline until private-only Health Model query evaluation is explicitly
supported and validated for the target region and API version:

- AMPLS `ingestionAccessMode`: `PrivateOnly`
- AMPLS `queryAccessMode`: `Open`
- Log Analytics `publicNetworkAccessForQuery`: `Enabled`
- Application Insights and Log Analytics local authentication: disabled where
  supported
- Health Model identity: least-privilege Azure RBAC

If private-only evaluation is confirmed in a non-production environment, change
one control at a time and verify signal refreshes before enforcing it in
production.

## Recommended architecture

```text
Foundry workload or OTEL exporter
        |
        | Private ingestion from the workload VNet
        v
AMPLS private endpoint
        |
        +--> Application Insights
                    |
                    v
          Log Analytics workspace
          AppMetrics and other tables
                    ^
                    |
                    | KQL query authenticated with managed identity
                    |
          Azure Monitor Health Model
```

The Health Model does not query an arbitrary OTLP endpoint. The telemetry must
first be stored in a supported Health Model data source:

- Log Analytics workspace for KQL signals.
- Azure Monitor workspace for PromQL signals.
- An Azure resource for platform metric signals.

For this repository, Foundry OTEL metrics are stored in `AppMetrics`, so a Log
Analytics signal is the correct signal type.

## Two-workspace alternative for a private primary workspace

Use a split-workspace design when policy permits a public, authenticated query
endpoint for sanitized health signals but prohibits that endpoint for raw
operational telemetry.

```text
Foundry workload or OTEL Collector
        |
        +-- Full telemetry ----------------> Private Application Insights
        |                                    Private operations workspace
        |                                    Public query disabled
        |
        +-- Approved metrics only ----------> Health Application Insights
                                             Health-signal workspace
                                             Public query enabled
                                                        ^
                                                        |
                                             Health Model managed identity
```

Configure the workspaces with different responsibilities:

| Setting | Private operations workspace | Health-signal workspace |
| --- | --- | --- |
| Data | Full logs, traces, exceptions, and sensitive dimensions | Allowlisted OTEL metrics or sanitized aggregates only |
| Ingestion | Private through AMPLS | Preferably private through the same AMPLS |
| Public query access | Disabled | Enabled |
| Local authentication | Disabled | Disabled |
| Health Model access | None | `Monitoring Reader` only |
| Retention | Operational and compliance requirement | Shortest period needed for health evaluation |

Enabling public query access on the health-signal workspace makes its endpoint
network-reachable. It does not permit anonymous queries. Microsoft Entra
authentication and Azure RBAC still authorize every request.

### Route data intentionally

Creating a second workspace does not copy data from the private workspace.
Cross-workspace KQL also does not create a network bridge: a query that
references the private workspace still requires query access to that workspace.

Use one of these routing patterns:

1. **OTEL Collector fan-out (preferred)** - Run a collector in the workload
   virtual network. Export complete telemetry to the private destination, then
   use filter and transform processors to send only approved, low-cardinality
   metrics to a second workspace-based Application Insights resource.
2. **Private projection worker** - Run a Function, Container App, or similar
   worker in the connected virtual network. Query the private workspace through
   AMPLS, calculate sanitized aggregates, and write only those values to the
   health-signal workspace.
3. **Multiple diagnostic settings where supported** - Route selected resource
   log categories to separate destinations. This option is resource-specific
   and does not automatically replicate Application Insights OTEL tables.

Do not duplicate the complete workspace unless the second workspace is allowed
to contain the same sensitive information as the first. Exclude prompt content,
model responses, user identifiers, exception bodies, raw request attributes,
and high-cardinality dimensions from the health-signal destination.

### Configure AMPLS for both workspaces

Use one AMPLS for networks that share DNS because Log Analytics query endpoints
are shared:

1. Add the private Application Insights component and its operations workspace
   to the AMPLS.
2. Add the health Application Insights component and health-signal workspace
   when private clients need to ingest into or query them.
3. Connect the AMPLS private endpoint to the workload virtual network.
4. Set public ingestion to disabled on both destinations after private
   ingestion is validated.
5. Keep public query disabled on the operations workspace.
6. Enable public query only on the health-signal workspace.
7. Grant the Health Model identity `Monitoring Reader` on the health-signal
   workspace only.

Clients in the connected virtual network use the shared private query endpoint.
The managed Health Model evaluator can use the public endpoint only for the
health-signal workspace because that resource explicitly permits public
queries.

### Repository impact

The current application configures one Azure Monitor exporter and one
Application Insights connection string in
[`Program.cs`](../src/ClinicalTrialChat.Api/Program.cs). Implementing
split-workspace routing requires an OTEL Collector or a separately configured
export pipeline.

The low-cardinality counters in
[`ChatTelemetry.cs`](../src/ClinicalTrialChat.Api/Services/ChatTelemetry.cs) are
appropriate candidates for the health-signal workspace. They intentionally omit
prompt text, response bodies, user identifiers, and status-code dimensions.
Keep application traces and general `ILogger` records in the private operations
workspace.

This design adds a workspace, ingestion charges, retention configuration, RBAC,
and a routing component. It also introduces propagation delay between the
original observation and Health Model evaluation.

## Application Insights and Log Analytics configuration

### 1. Confirm the OTEL destination

Enable monitoring for the Foundry project or configure the application OTEL
exporter to send metrics to the workspace-based Application Insights resource.
Verify that the expected metric names appear in `AppMetrics` before changing
network access.

This repository queries:

- `foundry.server_errors`
- `gen_ai.client.operation.duration`

The queries are defined in
[`health-model-observability.bicep`](../infra/health-model-observability.bicep).

### 2. Create the AMPLS private path

1. Create one AMPLS for networks that share the same DNS.
2. Create an AMPLS private endpoint in a subnet reachable from the Foundry
   workload or OTEL exporter.
3. Add the Application Insights component to the AMPLS.
4. Add the backing Log Analytics workspace to the same AMPLS.
5. Approve all private endpoint connections.
6. Link the Azure Monitor private DNS zones to the workload virtual network, or
   configure equivalent records and forwarding in the custom DNS service.
7. Allow HTTPS on port 443 from the workload to the private endpoint.

Use a single AMPLS for virtual networks that share DNS. Multiple AMPLS resources
can overwrite shared Azure Monitor endpoint records and break resolution.

### 3. Restrict ingestion

Generate test telemetry and confirm that it reaches Application Insights over
the private path. Then:

1. Set AMPLS ingestion access to `PrivateOnly`.
2. Disable public ingestion on Application Insights and Log Analytics where the
   selected collection path supports it.
3. Generate another metric and verify that it appears in `AppMetrics`.

Do not disable public ingestion before private endpoint approval, DNS, routing,
and firewall behavior have been validated.

### 4. Configure query access

Keep query access available to the managed Health Model evaluator:

1. Set AMPLS query access to `Open`.
2. Keep Log Analytics `publicNetworkAccessForQuery` set to `Enabled`.
3. Disable local or shared-key authentication where supported.
4. Scope RBAC to the specific workspace or smallest practical parent scope.

The sample currently sets public ingestion and query access to `Enabled` in
[`observability.bicep`](../infra/observability.bicep) and
[`resources.bicep`](../infra/resources.bicep). It does not currently provision
an AMPLS. Adopting this recommendation requires infrastructure changes beyond
the existing sample.

## Health Model identity and signal

The Health Model managed identity requires:

- `Reader` on Azure resources represented by Health Model entities.
- `Monitoring Reader` on each Log Analytics or Azure Monitor workspace queried
  by a signal.

Azure does not assign these roles automatically. This repository provisions the
relevant workspace access in
[`health-model-metrics.bicep`](../infra/health-model-metrics.bicep).

In the Health Model entity:

1. Add the backing Log Analytics workspace as the data source.
2. Select an authentication setting that uses the authorized Health Model
   identity.
3. Add a Log Analytics signal.
4. Use a KQL query against `AppMetrics`.
5. Make the final query result exactly one record with one numeric value.
6. Configure the refresh interval, query time range, and degraded and unhealthy
   thresholds.

Queries should explicitly handle an empty evaluation window. Returning zero
when the absence of matching records means no observed failures prevents an
idle workload from becoming `Unknown`.

## Managed Prometheus alternative

Use this path only when OTEL metrics are made available as Prometheus metrics in
an Azure Monitor workspace. An arbitrary external OTLP backend cannot be
selected directly as a Health Model data source.

For an Azure Monitor workspace:

1. Add the workspace's automatically created data collection endpoint to the
   AMPLS for private ingestion.
2. Create a separate private endpoint for query access with:
   - Resource type: `Microsoft.Monitor/accounts`
   - Target subresource: `prometheusMetrics`
3. Link the private DNS zone
   `privatelink.<region>.prometheus.monitor.azure.com`.
4. Grant the Health Model identity `Monitoring Reader` on the Azure Monitor
   workspace.
5. Configure an Azure Monitor workspace signal with a PromQL query that returns
   one numeric result.

The same Health Model evaluator caveat applies: validate service-side evaluation
before disabling the workspace public query endpoint.

## Strict private-query requirement

If policy prohibits a public query endpoint even for a minimized health-signal
workspace, the two-workspace design does not satisfy the requirement. If direct
Health Model signals cannot evaluate with private-only access, use an external
evaluator:

1. Run an Azure Function, Container App, or similar worker in the connected
   virtual network.
2. Query Log Analytics or the Azure Monitor workspace through the private
   endpoint.
3. Calculate the entity health state in that worker.
4. Submit the result to the Health Model as an externally evaluated signal by
   using the Health Report Ingestion API.

This preserves a private telemetry query path, but moves threshold evaluation
and operational ownership into the external component. Validate the outbound
path to the Health Report Ingestion API against the organization's network
policy.

## Validation checklist

- [ ] OTEL metrics appear in `AppMetrics` before network restrictions are
      applied.
- [ ] The workload resolves Azure Monitor ingestion endpoints through the
      expected private DNS path.
- [ ] Private endpoint connections are approved.
- [ ] The workload can reach the private endpoint on port 443.
- [ ] Metrics continue to arrive after public ingestion is disabled.
- [ ] The Health Model identity has workspace-level `Monitoring Reader`.
- [ ] The selected Health Model authentication setting uses that identity.
- [ ] The KQL or PromQL query returns one numeric result.
- [ ] Health Model signals continue refreshing with query access open.
- [ ] An unauthorized identity cannot query the workspace.
- [ ] A split health-signal workspace contains only approved metrics and
      dimensions.
- [ ] The Health Model identity has no access to the private operations
      workspace when the split-workspace design is used.
- [ ] Disabling public query access is tested only in non-production and is
      reverted if Health Model evaluation fails.

## Troubleshooting

| Symptom | Likely cause | Check |
| --- | --- | --- |
| No OTEL metrics arrive | Private ingestion path is incomplete | Private endpoint approval, DNS, routing, firewall, AMPLS resource membership |
| Query returns no rows | Metric name, role name, or time range does not match | `AppMetrics`, `Name`, `AppRoleName`, ingestion delay |
| Health Model reports authorization failure | Managed identity lacks data access | Authentication setting and `Monitoring Reader` scope |
| Signals fail only when public query is disabled | Evaluator has no private query route | Restore query access or use external evaluation |
| Health workspace query returns no rows | Telemetry is routed only to the private workspace | Collector fan-out or projection worker configuration |
| Sensitive data appears in the health workspace | Routing filter is too broad | Collector processors, metric allowlist, exported attributes |
| Signal remains `Unknown` | Query returns no numeric record | Add explicit empty-window handling |
| PromQL query fails privately | Azure Monitor workspace query endpoint is missing | `prometheusMetrics` private endpoint and regional private DNS zone |

## References

- [Export hosted agent telemetry by using OpenTelemetry](https://learn.microsoft.com/azure/foundry/agents/how-to/configure-hosted-agent-telemetry)
- [OpenTelemetry with Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/containers/opentelemetry-options)
- [Use Azure Private Link to connect networks to Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-security)
- [Configure private link for Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-configure)
- [Design Azure Monitor private link configuration](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-design)
- [Create an Azure Monitor Health Model](https://learn.microsoft.com/azure/azure-monitor/health-models/create)
- [Configure signals in Azure Monitor Health Models](https://learn.microsoft.com/azure/azure-monitor/health-models/signals)
- [Use private endpoints for Managed Prometheus and Azure Monitor workspace](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-azure-monitor-workspace)
- [Submit externally evaluated health signals](https://learn.microsoft.com/azure/azure-monitor/health-models/health-report-ingestion)
