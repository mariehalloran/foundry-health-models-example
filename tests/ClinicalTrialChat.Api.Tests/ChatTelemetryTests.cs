using System.Diagnostics.Metrics;
using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Tests;

public sealed class ChatTelemetryTests
{
    [Fact]
    public void RecordFoundryInputRejection_EmitsPrivacySafeCounter()
    {
        long? measurement = null;
        using var listener = new MeterListener
        {
            InstrumentPublished = (instrument, meterListener) =>
            {
                if (instrument.Meter.Name == ChatTelemetry.MeterName
                    && instrument.Name
                        == ChatTelemetry.FoundryInputRejectionsMetricName)
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

        ChatTelemetry.RecordFoundryInputRejection();

        Assert.Equal(1, measurement);
    }
}
