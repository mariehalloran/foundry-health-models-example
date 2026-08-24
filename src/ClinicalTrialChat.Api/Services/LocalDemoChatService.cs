using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public sealed class LocalDemoChatService : IFoundryChatService
{
    public Task<string> GetReplyAsync(
        IReadOnlyList<ConversationMessage> history,
        string userMessage,
        CancellationToken cancellationToken)
    {
        var normalizedMessage = userMessage.ToLowerInvariant();
        var reply = normalizedMessage switch
        {
            _ when normalizedMessage.Contains("previous", StringComparison.Ordinal)
                || normalizedMessage.Contains("remember", StringComparison.Ordinal) =>
                RecallPreviousQuestion(history),
            _ when normalizedMessage.Contains("screen", StringComparison.Ordinal) =>
                "A screening visit helps the study team check whether a trial may be " +
                "appropriate for you. It can include consent discussions, health-history " +
                "questions, and study-specific tests. Ask which tests, risks, and costs apply.",
            _ when normalizedMessage.Contains("side effect", StringComparison.Ordinal) =>
                "Contact the study team or a qualified health professional about side effects. " +
                "For severe or urgent symptoms, contact local emergency services now.",
            _ when normalizedMessage.Contains("cost", StringComparison.Ordinal)
                || normalizedMessage.Contains("pay", StringComparison.Ordinal) =>
                "Payment varies by study. Ask the study team which research costs, routine-care " +
                "costs, travel expenses, and insurance charges may apply.",
            _ when normalizedMessage.Contains("leave", StringComparison.Ordinal)
                || normalizedMessage.Contains("withdraw", StringComparison.Ordinal) =>
                "Clinical trial participation is voluntary, and participants can usually " +
                "withdraw. Ask the study team what follow-up is recommended if you leave.",
            _ when normalizedMessage.Contains("clinical trial", StringComparison.Ordinal) =>
                "A clinical trial is a research study involving people that evaluates health " +
                "interventions or ways to prevent, diagnose, or manage conditions.",
            _ =>
                "This local demo has canned responses rather than a live GPT connection. " +
                "Try one of the starter questions, or deploy to Azure for model-generated answers."
        };

        return Task.FromResult(reply);
    }

    private static string RecallPreviousQuestion(
        IReadOnlyList<ConversationMessage> history)
    {
        var previousQuestion = history
            .LastOrDefault(message => message.Role == "user")
            ?.Content;

        return previousQuestion is null
            ? "I do not have an earlier question in this local session yet."
            : $"Your previous question was: \"{previousQuestion}\"";
    }
}
