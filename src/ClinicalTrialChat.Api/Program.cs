using Azure.AI.OpenAI;
using Azure.Core;
using Azure.Identity;
using ClinicalTrialChat.Api.Configuration;
using ClinicalTrialChat.Api.Endpoints;
using ClinicalTrialChat.Api.Services;
using Microsoft.Azure.Cosmos;
using OpenAI.Chat;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddProblemDetails();
builder.Services.AddSingleton(_ =>
    FoundryOptions.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(_ =>
    CosmosOptions.FromConfiguration(builder.Configuration));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<TokenCredential>(_ => new DefaultAzureCredential());
builder.Services.AddSingleton<ChatClient>(services =>
{
    var credential = services.GetRequiredService<TokenCredential>();
    var options = services.GetRequiredService<FoundryOptions>();
    var client = new AzureOpenAIClient(options.Endpoint, credential);
    return client.GetChatClient(options.Deployment);
});
builder.Services.AddSingleton(services =>
{
    var credential = services.GetRequiredService<TokenCredential>();
    var options = services.GetRequiredService<CosmosOptions>();
    return new CosmosClient(
        options.Endpoint.ToString(),
        credential,
        new CosmosClientOptions
        {
            ApplicationName = "ClinicalTrialChat",
            UseSystemTextJsonSerializerWithOptions = new System.Text.Json.JsonSerializerOptions(
                System.Text.Json.JsonSerializerDefaults.Web)
        });
});
builder.Services.AddSingleton(services =>
{
    var client = services.GetRequiredService<CosmosClient>();
    var options = services.GetRequiredService<CosmosOptions>();
    return client.GetContainer(options.Database, options.Container);
});
builder.Services.AddSingleton<IStarterQuestionProvider, StarterQuestionProvider>();
builder.Services.AddSingleton<IConversationRepository, CosmosConversationRepository>();
builder.Services.AddSingleton<IFoundryChatService, AzureFoundryChatService>();
builder.Services.AddSingleton<ChatCoordinator>();

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));
app.MapChatEndpoints();
app.MapFallbackToFile("index.html");

app.Run();

public partial class Program;
