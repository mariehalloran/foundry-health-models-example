using System.Collections.Concurrent;
using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public sealed class InMemoryConversationRepository : IConversationRepository
{
    private readonly ConcurrentDictionary<string, List<ConversationMessage>> _messages =
        new(StringComparer.Ordinal);

    public Task<IReadOnlyList<ConversationMessage>> GetRecentAsync(
        string userId,
        int limit,
        CancellationToken cancellationToken)
    {
        if (limit <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(limit),
                "The message limit must be positive.");
        }

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
        if (!string.Equals(
                userMessage.UserId,
                assistantMessage.UserId,
                StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "Both messages in an exchange must belong to the same user.");
        }

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
