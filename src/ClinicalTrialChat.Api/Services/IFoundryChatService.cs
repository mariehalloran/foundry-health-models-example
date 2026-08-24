using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public interface IFoundryChatService
{
    Task<string> GetReplyAsync(
        IReadOnlyList<ConversationMessage> history,
        string userMessage,
        CancellationToken cancellationToken);
}
