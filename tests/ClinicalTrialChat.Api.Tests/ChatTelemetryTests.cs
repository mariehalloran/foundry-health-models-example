using System.Diagnostics.Metrics;
using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ChatTelemetryCollection
{
    public const string Name = "Chat telemetry";
}

[Collection(ChatTelemetryCollection.Name)]
public sealed class ChatTelemetryTests
{
    [Fact]
    public void RecordFoundryRequest_EmitsPrivacySafeCounter()
    {
        AssertPrivacySafeCounter(
            ChatTelemetry.FoundryRequestsMetricName,
            ChatTelemetry.RecordFoundryRequest);
    }

    [Fact]
    public void RecordFoundryServerError_EmitsPrivacySafeCounter()
    {
        AssertPrivacySafeCounter(
            ChatTelemetry.FoundryServerErrorsMetricName,
            ChatTelemetry.RecordFoundryServerError);
    }

    [Theory]
    [InlineData(499, false)]
    [InlineData(500, true)]
    [InlineData(503, true)]
    public void IsFoundryServerError_MatchesAvailabilityMetricDefinition(
        int statusCode,
        bool expected)
    {
        Assert.Equal(
            expected,
            ChatTelemetry.IsFoundryServerError(statusCode));
    }

    private static void AssertPrivacySafeCounter(
        string metricName,
        Action recordMeasurement)
    {
        long? measurement = null;
        using var listener = CreateListener(metricName);
        listener.SetMeasurementEventCallback<long>(
            (_, value, tags, _) =>
            {
                measurement = value;
                Assert.Empty(tags.ToArray());
            });
        listener.Start();

        recordMeasurement();

        Assert.Equal(1, measurement);
    }

    private static MeterListener CreateListener(params string[] metricNames) =>
        new()
        {
            InstrumentPublished = (instrument, meterListener) =>
            {
                if (instrument.Meter.Name == ChatTelemetry.MeterName
                    && metricNames.Contains(instrument.Name, StringComparer.Ordinal))
                {
                    meterListener.EnableMeasurementEvents(instrument);
                }
            }
        };
}
