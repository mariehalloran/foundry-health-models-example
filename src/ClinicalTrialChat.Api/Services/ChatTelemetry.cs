using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace ClinicalTrialChat.Api.Services;

public static class ChatTelemetry
{
    public const string ActivitySourceName = "ClinicalTrialChat.Api";
    public const string MeterName = "ClinicalTrialChat.Api";
    public const string FoundryServerErrorsMetricName = "foundry.server_errors";

    public static ActivitySource ActivitySource { get; } =
        new(ActivitySourceName);

    private static Meter Meter { get; } = new(MeterName);

    private static Counter<long> FoundryServerErrors { get; } =
        Meter.CreateCounter<long>(
            FoundryServerErrorsMetricName,
            unit: "{request}",
            description: "Foundry requests that returned an HTTP server error.");

    public static void RecordFoundryServerError() =>
        FoundryServerErrors.Add(1);

    internal static bool IsFoundryServerError(int statusCode) =>
        statusCode >= 500;

    public static Activity? StartDependency(
        string operationName,
        string dependencyType,
        string dependencyName)
    {
        var activity = ActivitySource.StartActivity(
            operationName,
            ActivityKind.Client);
        activity?.SetTag("dependency.type", dependencyType);
        activity?.SetTag("peer.service", dependencyName);
        return activity;
    }
}
