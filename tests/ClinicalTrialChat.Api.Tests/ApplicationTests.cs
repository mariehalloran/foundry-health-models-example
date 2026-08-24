using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using ClinicalTrialChat.Api.Models;
using ClinicalTrialChat.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace ClinicalTrialChat.Api.Tests;

public sealed class ApplicationTests : IClassFixture<ClinicalTrialApplicationFactory>
{
    private readonly HttpClient _client;

    public ApplicationTests(ClinicalTrialApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task HomePageAndHealthEndpoint_AreAvailable()
    {
        var home = await _client.GetStringAsync(
            "/",
            CancellationToken.None);
        var health = await _client.GetFromJsonAsync<HealthResponse>(
            "/health",
            CancellationToken.None);

        Assert.Contains("TrialGuide", home, StringComparison.Ordinal);
        Assert.Contains("type=\"module\"", home, StringComparison.Ordinal);
        Assert.Equal("healthy", health?.Status);
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
}

public sealed class ClinicalTrialApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Foundry:Endpoint"] = "https://example.openai.azure.com/",
                ["Foundry:Deployment"] = "test-chat",
                ["Cosmos:Endpoint"] = "https://example.documents.azure.com/",
                ["Cosmos:Database"] = "test-database",
                ["Cosmos:Container"] = "test-container"
            });
        });

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IConversationRepository>();
            services.RemoveAll<IFoundryChatService>();
            services.AddSingleton<IConversationRepository, InMemoryConversationRepository>();
            services.AddSingleton<IFoundryChatService, TestFoundryChatService>();
        });
    }
}

internal sealed class InMemoryConversationRepository : IConversationRepository
{
    private readonly ConcurrentDictionary<string, List<ConversationMessage>> _messages =
        new(StringComparer.Ordinal);

    public Task<IReadOnlyList<ConversationMessage>> GetRecentAsync(
        string userId,
        int limit,
        CancellationToken cancellationToken)
    {
        var messages = _messages.GetOrAdd(userId, _ => []);
        lock (messages)
        {
            IReadOnlyList<ConversationMessage> result = messages
                .OrderBy(message => message.CreatedAt)
                .TakeLast(limit)
                .ToList();
            return Task.FromResult(result);
        }
    }

    public Task SaveExchangeAsync(
        ConversationMessage userMessage,
        ConversationMessage assistantMessage,
        CancellationToken cancellationToken)
    {
        var messages = _messages.GetOrAdd(userMessage.UserId, _ => []);
        lock (messages)
        {
            messages.Add(userMessage);
            messages.Add(assistantMessage);
        }

        return Task.CompletedTask;
    }

    public Task DeleteUserHistoryAsync(
        string userId,
        CancellationToken cancellationToken)
    {
        _messages.TryRemove(userId, out _);
        return Task.CompletedTask;
    }
}

internal sealed class TestFoundryChatService : IFoundryChatService
{
    public Task<string> GetReplyAsync(
        IReadOnlyList<ConversationMessage> history,
        string userMessage,
        CancellationToken cancellationToken) =>
        Task.FromResult(
            "Screening commonly checks whether a study may be suitable. " +
            "Ask the study team which visits and records are required.");
}
