using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public sealed class ChatCoordinator(
    IConversationRepository conversationRepository,
    IFoundryChatService foundryChatService,
    TimeProvider timeProvider)
{
    public const int ContextMessageLimit = 12;
    public const int HistoryMessageLimit = 50;

    public Task<IReadOnlyList<ConversationMessage>> GetHistoryAsync(
        string userId,
        CancellationToken cancellationToken) =>
        conversationRepository.GetRecentAsync(
            userId,
            HistoryMessageLimit,
            cancellationToken);

    public async Task<ConversationMessage> SendAsync(
        string userId,
        string message,
        CancellationToken cancellationToken)
    {
        var history = await conversationRepository.GetRecentAsync(
            userId,
            ContextMessageLimit,
            cancellationToken);
        var reply = await foundryChatService.GetReplyAsync(
            history,
            message,
            cancellationToken);
        var createdAt = timeProvider.GetUtcNow();
        var userMessage = new ConversationMessage
        {
            Id = Guid.NewGuid().ToString("N"),
            UserId = userId,
            Role = "user",
            Content = message,
            CreatedAt = createdAt
        };
        var assistantMessage = new ConversationMessage
        {
            Id = Guid.NewGuid().ToString("N"),
            UserId = userId,
            Role = "assistant",
            Content = reply,
            CreatedAt = createdAt.AddTicks(1)
        };

        await conversationRepository.SaveExchangeAsync(
            userMessage,
            assistantMessage,
            cancellationToken);

        return assistantMessage;
    }

    public Task DeleteHistoryAsync(
        string userId,
        CancellationToken cancellationToken) =>
        conversationRepository.DeleteUserHistoryAsync(userId, cancellationToken);
}
