namespace ClinicalTrialChat.Api.Models;

public sealed record ConversationMessage
{
    public required string Id { get; init; }

    public required string UserId { get; init; }

    public required string Role { get; init; }

    public required string Content { get; init; }

    public required DateTimeOffset CreatedAt { get; init; }
}

public sealed record ConversationMessageDto(
    string Role,
    string Content,
    DateTimeOffset CreatedAt)
{
    public static ConversationMessageDto FromMessage(ConversationMessage message) =>
        new(message.Role, message.Content, message.CreatedAt);
}
