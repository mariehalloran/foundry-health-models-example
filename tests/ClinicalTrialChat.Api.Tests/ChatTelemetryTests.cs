using System.Diagnostics.Metrics;
using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Tests;

public sealed class ChatTelemetryTests
{
    [Fact]
    public void RecordFoundryServerError_EmitsPrivacySafeCounter()
    {
        long? measurement = null;
        using var listener = new MeterListener
        {
            InstrumentPublished = (instrument, meterListener) =>
            {
                if (instrument.Meter.Name == ChatTelemetry.MeterName
                    && instrument.Name
                        == ChatTelemetry.FoundryServerErrorsMetricName)
                {
                    meterListener.EnableMeasurementEvents(instrument);
                }
            }
        };
        listener.SetMeasurementEventCallback<long>(
            (_, value, tags, _) =>
            {
                measurement = value;
                Assert.Empty(tags.ToArray());
            });
        listener.Start();

        ChatTelemetry.RecordFoundryServerError();

        Assert.Equal(1, measurement);
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
}
