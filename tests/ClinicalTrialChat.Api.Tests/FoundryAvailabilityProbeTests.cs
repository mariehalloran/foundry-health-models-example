using System.Net;
using System.Collections.Concurrent;
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

        Assert.Equal(
            FoundryAvailabilityProbe.RequestsPerExecution,
            result.Requests.Count);
        Assert.All(result.Requests, result =>
        {
            Assert.Equal("OK", result.ResponseText);
            Assert.StartsWith(
                "request-",
                result.RequestId,
                StringComparison.Ordinal);
        });
        var scopes = Assert.IsType<string[]>(credential.Scopes);
        Assert.Equal(["https://ai.azure.com/.default"], scopes);
        Assert.Equal(1, credential.RequestCount);
        Assert.Equal(
            FoundryAvailabilityProbe.RequestsPerExecution,
            handler.Requests.Count);

        Assert.All(handler.Requests, request =>
        {
            Assert.Equal(
                new Uri("https://foundry.example/openai/v1/chat/completions"),
                request.RequestUri);
            Assert.Equal("Bearer", request.AuthorizationScheme);
            Assert.Equal("probe-token", request.AuthorizationParameter);

            using var body = JsonDocument.Parse(request.Body);
            Assert.Equal(
                "probe-model",
                body.RootElement.GetProperty("model").GetString());
            Assert.Equal(
                FoundryAvailabilityProbe.MaxCompletionTokens,
                body.RootElement
                    .GetProperty("max_completion_tokens")
                    .GetInt32());
            Assert.Equal(
                "Reply OK.",
                body.RootElement
                    .GetProperty("messages")[0]
                    .GetProperty("content")
                    .GetString());
            Assert.Single(
                body.RootElement.GetProperty("messages").EnumerateArray());
        });
    }

    [Fact]
    public async Task ExecuteAsync_FailsWhenAnyRequestFailsWithoutRetry()
    {
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
            """,
            requestNumber => requestNumber == 3
                ? HttpStatusCode.ServiceUnavailable
                : HttpStatusCode.OK);
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
        Assert.Contains("request-3", exception.Message, StringComparison.Ordinal);
        Assert.Equal(
            FoundryAvailabilityProbe.RequestsPerExecution,
            handler.Requests.Count);
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

        Assert.Contains("request-", exception.Message, StringComparison.Ordinal);
        Assert.Equal(
            FoundryAvailabilityProbe.RequestsPerExecution,
            handler.Requests.Count);
    }

    private sealed class RecordingTokenCredential : TokenCredential
    {
        public string[]? Scopes { get; private set; }

        public int RequestCount { get; private set; }

        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            Scopes = requestContext.Scopes;
            return CreateToken();
        }

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            Scopes = requestContext.Scopes;
            return ValueTask.FromResult(CreateToken());
        }

        private static AccessToken CreateToken() =>
            new("probe-token", DateTimeOffset.UtcNow.AddMinutes(5));
    }

    private sealed class RecordingHandler(
        string responseBody,
        Func<int, HttpStatusCode>? statusCodeProvider = null)
        : HttpMessageHandler
    {
        private readonly ConcurrentQueue<RecordedRequest> _requests = new();
        private int _requestCount;

        public RecordingHandler(
            string responseBody,
            HttpStatusCode statusCode)
            : this(responseBody, _ => statusCode)
        {
        }

        public IReadOnlyList<RecordedRequest> Requests =>
            _requests.ToArray();

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            var requestNumber = Interlocked.Increment(ref _requestCount);
            var requestBody = await request.Content!.ReadAsStringAsync(
                cancellationToken);
            _requests.Enqueue(new RecordedRequest(
                request.RequestUri,
                request.Headers.Authorization?.Scheme,
                request.Headers.Authorization?.Parameter,
                requestBody));

            var response = new HttpResponseMessage(
                statusCodeProvider?.Invoke(requestNumber) ?? HttpStatusCode.OK)
            {
                Content = new StringContent(
                    responseBody,
                    Encoding.UTF8,
                    "application/json")
            };
            response.Headers.Add("x-request-id", $"request-{requestNumber}");
            return response;
        }
    }

    private sealed record RecordedRequest(
        Uri? RequestUri,
        string? AuthorizationScheme,
        string? AuthorizationParameter,
        string Body);
}
