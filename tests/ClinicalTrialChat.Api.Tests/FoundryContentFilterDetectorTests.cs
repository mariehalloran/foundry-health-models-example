using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Tests;

public sealed class FoundryContentFilterDetectorTests
{
    [Theory]
    [InlineData(
        """{"error":{"code":"content_filter","param":"prompt"}}""",
        true)]
    [InlineData(
        """{"error":{"code":"BadRequest","innererror":{"code":"ResponsibleAIPolicyViolation"}}}""",
        true)]
    [InlineData(
        """{"error":{"code":"invalid_request_error","param":"model"}}""",
        false)]
    [InlineData("""{"error":""", false)]
    public void IsInputRejection_ClassifiesFoundryErrorPayload(
        string responseBody,
        bool expected)
    {
        var isRejection = FoundryContentFilterDetector.IsInputRejection(
            BinaryData.FromString(responseBody));

        Assert.Equal(expected, isRejection);
    }
}
