using System.Diagnostics;

namespace ClinicalTrialChat.Api.Services;

public static class ChatTelemetry
{
    public const string ActivitySourceName = "ClinicalTrialChat.Api";

    public static ActivitySource ActivitySource { get; } =
        new(ActivitySourceName);

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
