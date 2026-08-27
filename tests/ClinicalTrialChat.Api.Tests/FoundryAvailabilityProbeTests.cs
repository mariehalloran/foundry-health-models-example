using System.Net;
using System.Text;
using System.Text.Json;
using Azure.Core;
using ClinicalTrialChat.Probe;

namespace ClinicalTrialChat.Api.Tests;

public sealed class FoundryAvailabilityProbeTests
{
    [Fact]
    public void ProbeOptions_ReadsRequiredEnvironmentValues()
    {
        var clientId = Guid.NewGuid().ToString();
        var values = new Dictionary<string, string?>
        {
            ["AZURE_OPENAI_ENDPOINT"] = "https://foundry.example/",
            ["AZURE_OPENAI_DEPLOYMENT"] = "probe-model",
            ["AZURE_CLIENT_ID"] = clientId,
            ["PROBE_TIMEOUT_SECONDS"] = "30"
        };

        var options = ProbeOptions.FromValues(
            name => values.GetValueOrDefault(name));

        Assert.Equal(new Uri("https://foundry.example/"), options.Endpoint);
        Assert.Equal("probe-model", options.Deployment);
        Assert.Equal(clientId, options.ManagedIdentityClientId);
        Assert.Equal(TimeSpan.FromSeconds(30), options.Timeout);
    }

    [Fact]
    public void ProbeOptions_RejectsInvalidTimeout()
    {
        var values = new Dictionary<string, string?>
        {
            ["AZURE_OPENAI_ENDPOINT"] = "https://foundry.example/",
            ["AZURE_OPENAI_DEPLOYMENT"] = "probe-model",
            ["AZURE_CLIENT_ID"] = Guid.NewGuid().ToString(),
            ["PROBE_TIMEOUT_SECONDS"] = "60"
        };

        var exception = Assert.Throws<InvalidOperationException>(
            () => ProbeOptions.FromValues(
                name => values.GetValueOrDefault(name)));

        Assert.Contains(
            "PROBE_TIMEOUT_SECONDS",
            exception.Message,
            StringComparison.Ordinal);
    }

    [Fact]
    public async Task ExecuteAsync_SendsMinimalAuthenticatedChatCompletion()
    {
        var credential = new RecordingTokenCredential();
        var handler = new RecordingHandler(
            """
            {
              "choices": [
                {
                  "message": {
                    "content": "OK"
                  }
                }
              ]
            }
            """);
        using var httpClient = new HttpClient(handler);
        var options = new ProbeOptions(
            new Uri("https://foundry.example/"),
            "probe-model",
            Guid.NewGuid().ToString(),
            TimeSpan.FromSeconds(30));
        var probe = new FoundryAvailabilityProbe(
            httpClient,
            credential,
            options);

        var result = await probe.ExecuteAsync(CancellationToken.None);

        Assert.Equal("OK", result.ResponseText);
        Assert.Equal("request-123", result.RequestId);
        var scopes = Assert.IsType<string[]>(credential.Scopes);
        Assert.Equal(["https://ai.azure.com/.default"], scopes);
        Assert.NotNull(handler.Request);
        Assert.Equal(
            new Uri("https://foundry.example/openai/v1/chat/completions"),
            handler.Request.RequestUri);
        Assert.Equal(
            "Bearer",
            handler.Request.Headers.Authorization?.Scheme);
        Assert.Equal(
            "probe-token",
            handler.Request.Headers.Authorization?.Parameter);

        using var body = JsonDocument.Parse(handler.RequestBody!);
        Assert.Equal(
            "probe-model",
            body.RootElement.GetProperty("model").GetString());
        Assert.Equal(
            16,
            body.RootElement.GetProperty("max_completion_tokens").GetInt32());
        Assert.Single(body.RootElement.GetProperty("messages").EnumerateArray());
    }

    [Fact]
    public async Task ExecuteAsync_DoesNotRetryFailedFoundryCall()
    {
        var handler = new RecordingHandler(
            "{}",
            HttpStatusCode.ServiceUnavailable);
        using var httpClient = new HttpClient(handler);
        var options = new ProbeOptions(
            new Uri("https://foundry.example/"),
            "probe-model",
            Guid.NewGuid().ToString(),
            TimeSpan.FromSeconds(30));
        var probe = new FoundryAvailabilityProbe(
            httpClient,
            new RecordingTokenCredential(),
            options);

        var exception = await Assert.ThrowsAsync<HttpRequestException>(
            () => probe.ExecuteAsync(CancellationToken.None));

        Assert.Equal(HttpStatusCode.ServiceUnavailable, exception.StatusCode);
        Assert.Contains("request-123", exception.Message, StringComparison.Ordinal);
        Assert.Equal(1, handler.RequestCount);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsResponseWithoutModelText()
    {
        var handler = new RecordingHandler(
            """
            {
              "choices": [
                {
                  "message": {
                    "content": ""
                  }
                }
              ]
            }
            """);
        using var httpClient = new HttpClient(handler);
        var options = new ProbeOptions(
            new Uri("https://foundry.example/"),
            "probe-model",
            Guid.NewGuid().ToString(),
            TimeSpan.FromSeconds(30));
        var probe = new FoundryAvailabilityProbe(
            httpClient,
            new RecordingTokenCredential(),
            options);

        var exception = await Assert.ThrowsAsync<InvalidDataException>(
            () => probe.ExecuteAsync(CancellationToken.None));

        Assert.Contains("request-123", exception.Message, StringComparison.Ordinal);
        Assert.Equal(1, handler.RequestCount);
    }

    private sealed class RecordingTokenCredential : TokenCredential
    {
        public string[]? Scopes { get; private set; }

        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken)
        {
            Scopes = requestContext.Scopes;
            return CreateToken();
        }

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken)
        {
            Scopes = requestContext.Scopes;
            return ValueTask.FromResult(CreateToken());
        }

        private static AccessToken CreateToken() =>
            new("probe-token", DateTimeOffset.UtcNow.AddMinutes(5));
    }

    private sealed class RecordingHandler(
        string responseBody,
        HttpStatusCode statusCode = HttpStatusCode.OK)
        : HttpMessageHandler
    {
        public HttpRequestMessage? Request { get; private set; }

        public string? RequestBody { get; private set; }

        public int RequestCount { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            Request = request;
            RequestBody = await request.Content!.ReadAsStringAsync(
                cancellationToken);

            var response = new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(
                    responseBody,
                    Encoding.UTF8,
                    "application/json")
            };
            response.Headers.Add("x-request-id", "request-123");
            return response;
        }
    }
}
