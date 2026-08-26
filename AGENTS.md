## Learned preferences

- 2026-08-24 — Never hardcode or commit personal Azure subscription IDs, tenant IDs, account names, or contact emails; use ignored local configuration and placeholder examples. (source: user correction)
- 2026-08-24 — Keep Azure Health Model metric-access infrastructure in a standalone Bicep file rather than adding it to the main deployment template. (source: user correction)
- 2026-08-24 — Represent Azure Monitor, Application Insights, OpenTelemetry, Log Analytics, alerting, and workload-level health as distinct layers under the Health Model entity. (source: user correction)
- 2026-08-26 — Put Microsoft Foundry platform signals directly on the existing Foundry entity instead of creating child entities or relationships for them. (source: user correction)
- 2026-08-26 — Treat user-adjusted live Azure Health Model canvas positions as the source of truth and sync them into Bicep before redeployment. (source: user correction)
