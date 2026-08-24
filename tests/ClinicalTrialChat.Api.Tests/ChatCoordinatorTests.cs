using ClinicalTrialChat.Api.Models;
using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Tests;

public sealed class ChatCoordinatorTests
{
    [Fact]
    public async Task SendAsync_UsesBoundedHistoryAndSavesExchange()
    {
        var userId = $"demo-{Guid.NewGuid():D}";
        var history = new List<ConversationMessage>
        {
            Message(userId, "user", "What is screening?", 1),
            Message(userId, "assistant", "It is an initial review.", 2)
        };
        var repository = new RecordingConversationRepository(history);
        var foundry = new RecordingFoundryChatService("Ask the study team about next steps.");
        var now = new DateTimeOffset(2026, 8, 24, 16, 0, 0, TimeSpan.Zero);
        var coordinator = new ChatCoordinator(
            repository,
            foundry,
            new FixedTimeProvider(now));

        var reply = await coordinator.SendAsync(
            userId,
            "What should I ask next?",
            CancellationToken.None);

        Assert.Equal(ChatCoordinator.ContextMessageLimit, repository.LastRequestedLimit);
        Assert.Same(history, foundry.History);
        Assert.Equal("What should I ask next?", foundry.UserMessage);
        Assert.Equal("assistant", reply.Role);
        Assert.Equal("Ask the study team about next steps.", reply.Content);
        Assert.Equal(2, repository.SavedMessages.Count);
        Assert.Equal("user", repository.SavedMessages[0].Role);
        Assert.Equal(now, repository.SavedMessages[0].CreatedAt);
        Assert.Equal("assistant", repository.SavedMessages[1].Role);
        Assert.True(
            repository.SavedMessages[1].CreatedAt
            > repository.SavedMessages[0].CreatedAt);
    }

    private static ConversationMessage Message(
        string userId,
        string role,
        string content,
        int second) =>
        new()
        {
            Id = Guid.NewGuid().ToString("N"),
            UserId = userId,
            Role = role,
            Content = content,
            CreatedAt = new DateTimeOffset(
                2026,
                8,
                24,
                16,
                0,
                second,
                TimeSpan.Zero)
        };

    private sealed class RecordingConversationRepository(
        IReadOnlyList<ConversationMessage> history) : IConversationRepository
    {
        public int LastRequestedLimit { get; private set; }

        public List<ConversationMessage> SavedMessages { get; } = [];

        public Task<IReadOnlyList<ConversationMessage>> GetRecentAsync(
            string userId,
            int limit,
            CancellationToken cancellationToken)
        {
            LastRequestedLimit = limit;
            return Task.FromResult(history);
        }

        public Task SaveExchangeAsync(
            ConversationMessage userMessage,
            ConversationMessage assistantMessage,
            CancellationToken cancellationToken)
        {
            SavedMessages.Add(userMessage);
            SavedMessages.Add(assistantMessage);
            return Task.CompletedTask;
        }

        public Task DeleteUserHistoryAsync(
            string userId,
            CancellationToken cancellationToken) =>
            Task.CompletedTask;
    }

    private sealed class RecordingFoundryChatService(string reply)
        : IFoundryChatService
    {
        public IReadOnlyList<ConversationMessage>? History { get; private set; }

        public string? UserMessage { get; private set; }

        public Task<string> GetReplyAsync(
            IReadOnlyList<ConversationMessage> history,
            string userMessage,
            CancellationToken cancellationToken)
        {
            History = history;
            UserMessage = userMessage;
            return Task.FromResult(reply);
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
