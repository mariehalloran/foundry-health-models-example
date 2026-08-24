using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public sealed class ChatCoordinator(
    IConversationRepository conversationRepository,
    IFoundryChatService foundryChatService,
    TimeProvider timeProvider)
{
    public const int ContextMessageLimit = 12;
    public const int HistoryMessageLimit = 50;

    public async Task<IReadOnlyList<ConversationMessage>> GetHistoryAsync(
        string userId,
        CancellationToken cancellationToken)
    {
        using var activity = ChatTelemetry.StartDependency(
            "conversation.history.read",
            "Azure Cosmos DB",
            "conversation-memory");
        var history = await conversationRepository.GetRecentAsync(
            userId,
            HistoryMessageLimit,
            cancellationToken);
        activity?.SetTag("conversation.message.count", history.Count);
        return history;
    }

    public async Task<ConversationMessage> SendAsync(
        string userId,
        string message,
        CancellationToken cancellationToken)
    {
        using var requestActivity = ChatTelemetry.ActivitySource.StartActivity(
            "chat.process",
            System.Diagnostics.ActivityKind.Internal);
        requestActivity?.SetTag("chat.input.length", message.Length);

        IReadOnlyList<ConversationMessage> history;
        using (var memoryActivity = ChatTelemetry.StartDependency(
                   "conversation.context.read",
                   "Azure Cosmos DB",
                   "conversation-memory"))
        {
            history = await conversationRepository.GetRecentAsync(
                userId,
                ContextMessageLimit,
                cancellationToken);
            memoryActivity?.SetTag("conversation.message.count", history.Count);
        }

        string reply;
        using (var modelActivity = ChatTelemetry.StartDependency(
                   "foundry.chat.complete",
                   "Microsoft Foundry",
                   "gpt-chat"))
        {
            modelActivity?.SetTag("gen_ai.system", "azure.openai");
            modelActivity?.SetTag("gen_ai.operation.name", "chat");
            reply = await foundryChatService.GetReplyAsync(
                history,
                message,
                cancellationToken);
        }

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

        using (var memoryActivity = ChatTelemetry.StartDependency(
                   "conversation.exchange.write",
                   "Azure Cosmos DB",
                   "conversation-memory"))
        {
            await conversationRepository.SaveExchangeAsync(
                userMessage,
                assistantMessage,
                cancellationToken);
        }

        requestActivity?.SetTag("chat.output.length", reply.Length);
        return assistantMessage;
    }

    public async Task DeleteHistoryAsync(
        string userId,
        CancellationToken cancellationToken)
    {
        using var activity = ChatTelemetry.StartDependency(
            "conversation.history.delete",
            "Azure Cosmos DB",
            "conversation-memory");
        await conversationRepository.DeleteUserHistoryAsync(
            userId,
            cancellationToken);
    }
}
