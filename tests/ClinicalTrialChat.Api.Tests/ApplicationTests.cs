using System.Net;
using System.Net.Http.Json;
using ClinicalTrialChat.Api.Models;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace ClinicalTrialChat.Api.Tests;

public sealed class ApplicationTests : IClassFixture<ClinicalTrialApplicationFactory>
{
    private readonly HttpClient _client;

    public ApplicationTests(ClinicalTrialApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task ApiRootAndHealthEndpoints_AreAvailable()
    {
        var root = await _client.GetFromJsonAsync<ServiceResponse>(
            "/",
            CancellationToken.None);
        var health = await _client.GetFromJsonAsync<HealthResponse>(
            "/health",
            CancellationToken.None);
        var proxiedHealth = await _client.GetFromJsonAsync<HealthResponse>(
            "/api/health",
            CancellationToken.None);
        var runtime = await _client.GetFromJsonAsync<RuntimeResponse>(
            "/api/runtime",
            CancellationToken.None);

        Assert.Equal("clinical-trial-chat-api", root?.Service);
        Assert.Equal("healthy", health?.Status);
        Assert.Equal("healthy", proxiedHealth?.Status);
        Assert.Equal("local-demo", runtime?.Mode);
    }

    [Fact]
    public async Task Api_AllowsConfiguredLocalFrontendOrigin()
    {
        using var request = new HttpRequestMessage(HttpMethod.Options, "/api/questions");
        request.Headers.Add("Origin", "http://localhost:5173");
        request.Headers.Add("Access-Control-Request-Method", "GET");

        var response = await _client.SendAsync(request, CancellationToken.None);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(
            "http://localhost:5173",
            Assert.Single(response.Headers.GetValues("Access-Control-Allow-Origin")));
    }

    [Fact]
    public async Task QuestionsEndpoint_ReturnsCuratedQuestions()
    {
        var questions = await _client.GetFromJsonAsync<List<StarterQuestion>>(
            "/api/questions",
            CancellationToken.None);

        Assert.NotNull(questions);
        Assert.Equal(6, questions.Count);
        Assert.Contains(
            questions,
            question => question.Text == "What is a clinical trial?");
    }

    [Fact]
    public async Task ChatHistory_CanBeRememberedAndDeleted()
    {
        var userId = $"demo-{Guid.NewGuid():D}";
        var chatResponse = await _client.PostAsJsonAsync(
            "/api/chat",
            new ChatRequest(userId, "What happens during screening?"),
            CancellationToken.None);
        chatResponse.EnsureSuccessStatusCode();

        var history = await _client.GetFromJsonAsync<List<ConversationMessageDto>>(
            $"/api/history/{userId}",
            CancellationToken.None);

        Assert.NotNull(history);
        Assert.Collection(
            history,
            message =>
            {
                Assert.Equal("user", message.Role);
                Assert.Equal("What happens during screening?", message.Content);
            },
            message =>
            {
                Assert.Equal("assistant", message.Role);
                Assert.Contains("study team", message.Content, StringComparison.OrdinalIgnoreCase);
            });

        var deleteResponse = await _client.DeleteAsync(
            $"/api/history/{userId}",
            CancellationToken.None);
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var deletedHistory = await _client.GetFromJsonAsync<List<ConversationMessageDto>>(
            $"/api/history/{userId}",
            CancellationToken.None);
        Assert.Empty(deletedHistory!);
    }

    private sealed record HealthResponse(string Status);

    private sealed record ServiceResponse(string Service);
}

public sealed class ClinicalTrialApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["LocalDemo:Enabled"] = "true",
                ["Frontend:AllowedOrigins:0"] = "http://localhost:5173"
            });
        });
    }
}

internal sealed record RuntimeResponse(string Mode);
