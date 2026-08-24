using ClinicalTrialChat.Api.Configuration;
using ClinicalTrialChat.Api.Models;
using OpenAI.Chat;

namespace ClinicalTrialChat.Api.Services;

public sealed class AzureFoundryChatService(
    ChatClient chatClient,
    FoundryOptions options,
    IStarterQuestionProvider questionProvider) : IFoundryChatService
{
    private readonly string _systemPrompt =
        ClinicalTrialPrompt.Build(questionProvider.Questions);

    public async Task<string> GetReplyAsync(
        IReadOnlyList<ConversationMessage> history,
        string userMessage,
        CancellationToken cancellationToken)
    {
        List<ChatMessage> messages =
        [
            new SystemChatMessage(_systemPrompt)
        ];

        foreach (var message in history)
        {
            messages.Add(message.Role switch
            {
                "user" => new UserChatMessage(message.Content),
                "assistant" => new AssistantChatMessage(message.Content),
                _ => throw new InvalidOperationException(
                    $"Unsupported stored chat role '{message.Role}'.")
            });
        }

        messages.Add(new UserChatMessage(userMessage));

        var completionOptions = new ChatCompletionOptions
        {
            MaxOutputTokenCount = options.MaxOutputTokens
        };
        ChatCompletion completion = await chatClient.CompleteChatAsync(
            messages,
            completionOptions,
            cancellationToken);
        var reply = string.Concat(completion.Content.Select(part => part.Text)).Trim();

        if (string.IsNullOrWhiteSpace(reply))
        {
            throw new InvalidOperationException(
                "Microsoft Foundry returned an empty chat response.");
        }

        return reply;
    }
}
