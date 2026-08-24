using ClinicalTrialChat.Api.Models;
using Microsoft.Azure.Cosmos;

namespace ClinicalTrialChat.Api.Services;

public sealed class CosmosConversationRepository(Container container)
    : IConversationRepository
{
    private const int MaxBatchOperations = 100;

    public async Task<IReadOnlyList<ConversationMessage>> GetRecentAsync(
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

        var query = new QueryDefinition(
                "SELECT TOP @limit * FROM messages m " +
                "WHERE m.userId = @userId ORDER BY m.createdAt DESC")
            .WithParameter("@limit", limit)
            .WithParameter("@userId", userId);
        using var iterator = container.GetItemQueryIterator<ConversationMessage>(
            query,
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(userId),
                MaxItemCount = limit
            });

        var messages = new List<ConversationMessage>(limit);
        while (iterator.HasMoreResults && messages.Count < limit)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            messages.AddRange(page);
        }

        messages.Reverse();
        return messages;
    }

    public async Task SaveExchangeAsync(
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

        var batch = container
            .CreateTransactionalBatch(new PartitionKey(userMessage.UserId))
            .CreateItem(userMessage)
            .CreateItem(assistantMessage);
        using var response = await batch.ExecuteAsync(cancellationToken);

        EnsureBatchSucceeded(response, "save the chat exchange");
    }

    public async Task DeleteUserHistoryAsync(
        string userId,
        CancellationToken cancellationToken)
    {
        var query = new QueryDefinition(
                "SELECT VALUE m.id FROM messages m WHERE m.userId = @userId")
            .WithParameter("@userId", userId);
        using var iterator = container.GetItemQueryIterator<string>(
            query,
            requestOptions: new QueryRequestOptions
            {
                PartitionKey = new PartitionKey(userId),
                MaxItemCount = MaxBatchOperations
            });

        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(cancellationToken);
            foreach (var ids in page.Chunk(MaxBatchOperations))
            {
                var batch = container.CreateTransactionalBatch(
                    new PartitionKey(userId));
                foreach (var id in ids)
                {
                    batch.DeleteItem(id);
                }

                using var response = await batch.ExecuteAsync(cancellationToken);
                EnsureBatchSucceeded(response, "delete the user's chat history");
            }
        }
    }

    private static void EnsureBatchSucceeded(
        TransactionalBatchResponse response,
        string operation)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"Cosmos DB could not {operation}. " +
                $"Status: {(int)response.StatusCode} ({response.StatusCode}). " +
                $"Details: {response.ErrorMessage}");
        }
    }
}
