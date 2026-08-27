using System.Diagnostics;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Azure.Core;

namespace ClinicalTrialChat.Probe;

internal sealed class FoundryAvailabilityProbe(
    HttpClient httpClient,
    TokenCredential credential,
    ProbeOptions options)
{
    private const int MaxCompletionTokens = 16;
    private static readonly string[] TokenScopes = ["https://ai.azure.com/.default"];
    private readonly Uri _requestUri =
        new(options.Endpoint, "openai/v1/chat/completions");

    public async Task<ProbeResult> ExecuteAsync(CancellationToken cancellationToken)
    {
        var accessToken = await credential.GetTokenAsync(
            new TokenRequestContext(TokenScopes),
            cancellationToken);

        using var request = new HttpRequestMessage(HttpMethod.Post, _requestUri);
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", accessToken.Token);
        request.Headers.UserAgent.ParseAdd("clinical-trial-chat-foundry-probe/1.0");
        request.Content = JsonContent.Create(new
        {
            model = options.Deployment,
            messages = new[]
            {
                new
                {
                    role = "user",
                    content = "Reply with the single word OK."
                }
            },
            max_completion_tokens = MaxCompletionTokens
        });

        var stopwatch = Stopwatch.StartNew();
        using var response = await httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        stopwatch.Stop();

        var requestId = GetRequestId(response);
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"Foundry probe returned HTTP {(int)response.StatusCode} " +
                $"({response.ReasonPhrase}). Request ID: {requestId ?? "unavailable"}.",
                inner: null,
                response.StatusCode);
        }

        await using var responseStream = await response.Content.ReadAsStreamAsync(
            cancellationToken);
        using var document = await JsonDocument.ParseAsync(
            responseStream,
            cancellationToken: cancellationToken);

        if (!TryGetResponseText(document.RootElement, out var responseText))
        {
            throw new InvalidDataException(
                $"Foundry probe returned no model text. Request ID: " +
                $"{requestId ?? "unavailable"}.");
        }

        return new ProbeResult(stopwatch.Elapsed, requestId, responseText);
    }

    private static bool TryGetResponseText(
        JsonElement root,
        out string responseText)
    {
        responseText = string.Empty;
        if (!root.TryGetProperty("choices", out var choices)
            || choices.ValueKind != JsonValueKind.Array
            || choices.GetArrayLength() == 0
            || !choices[0].TryGetProperty("message", out var message)
            || !message.TryGetProperty("content", out var content)
            || content.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        responseText = content.GetString()?.Trim() ?? string.Empty;
        return responseText.Length > 0;
    }

    private static string? GetRequestId(HttpResponseMessage response)
    {
        foreach (var headerName in new[] { "x-request-id", "apim-request-id" })
        {
            if (response.Headers.TryGetValues(headerName, out var values))
            {
                return values.FirstOrDefault();
            }
        }

        return null;
    }
}

internal sealed record ProbeResult(
    TimeSpan Duration,
    string? RequestId,
    string ResponseText);
