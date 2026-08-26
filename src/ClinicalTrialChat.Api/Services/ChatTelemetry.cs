using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace ClinicalTrialChat.Api.Services;

public static class ChatTelemetry
{
    public const string ActivitySourceName = "ClinicalTrialChat.Api";
    public const string MeterName = "ClinicalTrialChat.Api";
    public const string FoundryInputRejectionsMetricName =
        "foundry.content_filter.input_rejections";

    public static ActivitySource ActivitySource { get; } =
        new(ActivitySourceName);

    private static Meter Meter { get; } = new(MeterName);

    private static Counter<long> FoundryInputRejections { get; } =
        Meter.CreateCounter<long>(
            FoundryInputRejectionsMetricName,
            unit: "{request}",
            description: "Foundry requests rejected because the input triggered content filters.");

    public static void RecordFoundryInputRejection() =>
        FoundryInputRejections.Add(1);

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
