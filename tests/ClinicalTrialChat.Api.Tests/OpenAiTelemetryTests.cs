using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Text;
using ClinicalTrialChat.Api.Services;
using OpenAI;
using OpenAI.Chat;
using System.ClientModel;
using System.ClientModel.Primitives;

namespace ClinicalTrialChat.Api.Tests;

public sealed class OpenAiTelemetryTests
{
    [Fact]
    public async Task CompleteChatAsync_EmitsGenAiClientSpanWithoutMessageContent()
    {
        var stoppedActivities = new ConcurrentQueue<Activity>();
        using var listener = new ActivityListener
        {
            ShouldListenTo = source =>
                source.Name == ChatTelemetry.OpenAiTelemetryName,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) =>
                ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = stoppedActivities.Enqueue
        };
        ActivitySource.AddActivityListener(listener);
        AppContext.SetSwitch("OpenAI.Experimental.EnableOpenTelemetry", true);

        try
        {
            using var httpClient = new HttpClient(new ChatCompletionHandler());
            var client = new ChatClient(
                "test-deployment",
                new ApiKeyCredential("test-key"),
                new OpenAIClientOptions
                {
                    Endpoint = new Uri("https://foundry.example/openai/v1/"),
                    Transport = new HttpClientPipelineTransport(httpClient)
                });

            await client.CompleteChatAsync(
                [new UserChatMessage("private test prompt")],
                new ChatCompletionOptions(),
                CancellationToken.None);

            var activity = Assert.Single(stoppedActivities);
            Assert.Equal("chat test-deployment", activity.DisplayName);
            Assert.Equal("chat", activity.GetTagItem("gen_ai.operation.name"));
            Assert.Equal("openai", activity.GetTagItem("gen_ai.system"));
            Assert.Equal(
                "test-deployment",
                activity.GetTagItem("gen_ai.request.model"));
            Assert.Equal("foundry.example", activity.GetTagItem("server.address"));
            Assert.DoesNotContain(
                activity.Tags,
                tag => tag.Value?.Contains(
                    "private test prompt",
                    StringComparison.Ordinal) == true);
            Assert.DoesNotContain(
                activity.Tags,
                tag => tag.Value?.Contains(
                    "private test response",
                    StringComparison.Ordinal) == true);
        }
        finally
        {
            AppContext.SetSwitch("OpenAI.Experimental.EnableOpenTelemetry", false);
        }
    }

    private sealed class ChatCompletionHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            const string responseBody = """
                {
                  "id": "chatcmpl-test",
                  "object": "chat.completion",
                  "created": 1787832000,
                  "model": "test-response-model",
                  "choices": [
                    {
                      "index": 0,
                      "message": {
                        "role": "assistant",
                        "content": "private test response"
                      },
                      "finish_reason": "stop"
                    }
                  ],
                  "usage": {
                    "prompt_tokens": 3,
                    "completion_tokens": 3,
                    "total_tokens": 6
                  }
                }
                """;

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    responseBody,
                    Encoding.UTF8,
                    "application/json"),
                RequestMessage = request
            });
        }
    }
}
