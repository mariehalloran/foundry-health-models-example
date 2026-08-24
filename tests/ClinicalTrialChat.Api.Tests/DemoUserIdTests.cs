using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Tests;

public sealed class DemoUserIdTests
{
    [Fact]
    public void TryNormalize_AcceptsDemoGuid()
    {
        var id = Guid.NewGuid();

        var isValid = DemoUserId.TryNormalize($"DEMO-{id:D}", out var normalized);

        Assert.True(isValid);
        Assert.Equal($"demo-{id:D}", normalized);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("demo-not-a-guid")]
    [InlineData("user-00000000-0000-0000-0000-000000000000")]
    public void TryNormalize_RejectsInvalidValues(string? value)
    {
        Assert.False(DemoUserId.TryNormalize(value, out _));
    }
}
