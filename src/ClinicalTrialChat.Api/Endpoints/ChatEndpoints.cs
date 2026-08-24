using ClinicalTrialChat.Api.Models;
using ClinicalTrialChat.Api.Services;

namespace ClinicalTrialChat.Api.Endpoints;

public static class ChatEndpoints
{
    private const int MaxMessageLength = 2_000;

    public static IEndpointRouteBuilder MapChatEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        var api = endpoints.MapGroup("/api");

        api.MapGet(
            "/questions",
            (IStarterQuestionProvider provider) =>
                Results.Ok(provider.Questions));

        api.MapGet(
            "/history/{userId}",
            async (
                string userId,
                ChatCoordinator coordinator,
                CancellationToken cancellationToken) =>
            {
                if (!DemoUserId.TryNormalize(userId, out var normalizedUserId))
                {
                    return InvalidUserId();
                }

                var history = await coordinator.GetHistoryAsync(
                    normalizedUserId,
                    cancellationToken);
                return Results.Ok(history.Select(
                    ConversationMessageDto.FromMessage));
            });

        api.MapPost(
            "/chat",
            async (
                ChatRequest request,
                ChatCoordinator coordinator,
                CancellationToken cancellationToken) =>
            {
                if (!DemoUserId.TryNormalize(request.UserId, out var userId))
                {
                    return InvalidUserId();
                }

                var message = request.Message?.Trim();
                if (string.IsNullOrWhiteSpace(message))
                {
                    return Results.ValidationProblem(new Dictionary<string, string[]>
                    {
                        ["message"] = ["Enter a question before sending."]
                    });
                }

                if (message.Length > MaxMessageLength)
                {
                    return Results.ValidationProblem(new Dictionary<string, string[]>
                    {
                        ["message"] =
                        [
                            $"Questions must be {MaxMessageLength} characters or fewer."
                        ]
                    });
                }

                var reply = await coordinator.SendAsync(
                    userId,
                    message,
                    cancellationToken);
                return Results.Ok(new ChatResponse(
                    ConversationMessageDto.FromMessage(reply)));
            });

        api.MapDelete(
            "/history/{userId}",
            async (
                string userId,
                ChatCoordinator coordinator,
                CancellationToken cancellationToken) =>
            {
                if (!DemoUserId.TryNormalize(userId, out var normalizedUserId))
                {
                    return InvalidUserId();
                }

                await coordinator.DeleteHistoryAsync(
                    normalizedUserId,
                    cancellationToken);
                return Results.NoContent();
            });

        return endpoints;
    }

    private static IResult InvalidUserId() =>
        Results.ValidationProblem(new Dictionary<string, string[]>
        {
            ["userId"] = ["The user ID must use the demo-<GUID> format."]
        });
}
