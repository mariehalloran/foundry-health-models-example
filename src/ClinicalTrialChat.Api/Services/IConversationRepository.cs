using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public interface IConversationRepository
{
    Task<IReadOnlyList<ConversationMessage>> GetRecentAsync(
        string userId,
        int limit,
        CancellationToken cancellationToken);

    Task SaveExchangeAsync(
        ConversationMessage userMessage,
        ConversationMessage assistantMessage,
        CancellationToken cancellationToken);

    Task DeleteUserHistoryAsync(string userId, CancellationToken cancellationToken);
}
