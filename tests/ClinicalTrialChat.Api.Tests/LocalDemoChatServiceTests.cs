using ClinicalTrialChat.Api.Models;
using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Tests;

public sealed class LocalDemoChatServiceTests
{
    [Fact]
    public async Task GetReplyAsync_RecallsPreviousUserQuestion()
    {
        var service = new LocalDemoChatService();
        IReadOnlyList<ConversationMessage> history =
        [
            new ConversationMessage
            {
                Id = Guid.NewGuid().ToString("N"),
                UserId = $"demo-{Guid.NewGuid():D}",
                Role = "user",
                Content = "What happens during screening?",
                CreatedAt = DateTimeOffset.UtcNow
            }
        ];

        var reply = await service.GetReplyAsync(
            history,
            "What did I ask previously?",
            CancellationToken.None);

        Assert.Contains(
            "What happens during screening?",
            reply,
            StringComparison.Ordinal);
    }
}
