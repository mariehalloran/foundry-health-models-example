using System.ClientModel;
using System.Text.Json;

namespace ClinicalTrialChat.Api.Services;

internal static class FoundryContentFilterDetector
{
    private const int BadRequestStatusCode = 400;

    internal static bool IsInputRejection(ClientResultException exception)
    {
        ArgumentNullException.ThrowIfNull(exception);

        var response = exception.GetRawResponse();
        return exception.Status == BadRequestStatusCode
            && response is not null
            && IsInputRejection(response.Content);
    }

    internal static bool IsInputRejection(BinaryData responseContent)
    {
        ArgumentNullException.ThrowIfNull(responseContent);

        try
        {
            using var document = JsonDocument.Parse(responseContent.ToMemory());
            if (!document.RootElement.TryGetProperty("error", out var error)
                || error.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            return HasCode(error, "content_filter")
                || error.TryGetProperty("innererror", out var innerError)
                    && innerError.ValueKind == JsonValueKind.Object
                    && HasCode(innerError, "ResponsibleAIPolicyViolation");
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool HasCode(JsonElement error, string expectedCode) =>
        error.TryGetProperty("code", out var code)
        && code.ValueKind == JsonValueKind.String
        && string.Equals(
            code.GetString(),
            expectedCode,
            StringComparison.OrdinalIgnoreCase);
}
