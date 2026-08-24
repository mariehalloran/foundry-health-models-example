using Azure.Core;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using ClinicalTrialChat.Api.Configuration;
using ClinicalTrialChat.Api.Endpoints;
using ClinicalTrialChat.Api.Services;
using Microsoft.Azure.Cosmos;
using OpenAI;
using OpenAI.Chat;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System.ClientModel.Primitives;

var builder = WebApplication.CreateBuilder(args);
var useLocalDemo = builder.Configuration.GetValue<bool>("LocalDemo:Enabled");
var allowedFrontendOrigins = builder.Configuration
    .GetSection("Frontend:AllowedOrigins")
    .GetChildren()
    .Select(origin => origin.Value)
    .OfType<string>()
    .Where(origin => !string.IsNullOrWhiteSpace(origin))
    .ToArray();

builder.Services.AddProblemDetails();

var appInsightsConnectionString =
    builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    var clientId = builder.Configuration["AZURE_CLIENT_ID"];
    builder.Services
        .AddOpenTelemetry()
        .UseAzureMonitor(options =>
        {
            options.ConnectionString = appInsightsConnectionString;
            options.Credential = string.IsNullOrWhiteSpace(clientId)
                ? new DefaultAzureCredential()
                : new ManagedIdentityCredential(
                    ManagedIdentityId.FromUserAssignedClientId(clientId));
        })
        .ConfigureResource(resource => resource.AddService(
            serviceName: "clinical-trial-chat-api",
            serviceNamespace: "clinical-trial-chat",
            serviceInstanceId: Environment.MachineName));
    builder.Services.ConfigureOpenTelemetryTracerProvider(
        (_, tracing) => tracing.AddSource(ChatTelemetry.ActivitySourceName));
}

builder.Services.AddCors(options =>
{
    options.AddPolicy("Frontend", policy =>
    {
        if (allowedFrontendOrigins.Length > 0)
        {
            policy
                .WithOrigins(allowedFrontendOrigins)
                .AllowAnyHeader()
                .WithMethods("GET", "POST", "DELETE");
        }
    });
});
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<IStarterQuestionProvider, StarterQuestionProvider>();

if (useLocalDemo)
{
    builder.Services.AddSingleton<IConversationRepository, InMemoryConversationRepository>();
    builder.Services.AddSingleton<IFoundryChatService, LocalDemoChatService>();
}
else
{
    builder.Services.AddSingleton(_ =>
        FoundryOptions.FromConfiguration(builder.Configuration));
    builder.Services.AddSingleton(_ =>
        CosmosOptions.FromConfiguration(builder.Configuration));
    builder.Services.AddSingleton<TokenCredential>(_ => new DefaultAzureCredential());
    builder.Services.AddSingleton<ChatClient>(services =>
    {
        var credential = services.GetRequiredService<TokenCredential>();
        var options = services.GetRequiredService<FoundryOptions>();
        var tokenPolicy = new BearerTokenPolicy(
            credential,
            "https://ai.azure.com/.default");

#pragma warning disable OPENAI001
        return new ChatClient(
            options.Deployment,
            tokenPolicy,
            new OpenAIClientOptions
            {
                Endpoint = new Uri(options.Endpoint, "openai/v1/")
            });
#pragma warning restore OPENAI001
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
                UseSystemTextJsonSerializerWithOptions =
                    new System.Text.Json.JsonSerializerOptions(
                        System.Text.Json.JsonSerializerDefaults.Web)
            });
    });
    builder.Services.AddSingleton(services =>
    {
        var client = services.GetRequiredService<CosmosClient>();
        var options = services.GetRequiredService<CosmosOptions>();
        return client.GetContainer(options.Database, options.Container);
    });
    builder.Services.AddSingleton<IConversationRepository, CosmosConversationRepository>();
    builder.Services.AddSingleton<IFoundryChatService, AzureFoundryChatService>();
}

builder.Services.AddSingleton<ChatCoordinator>();

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseCors("Frontend");

app.MapGet("/", () => Results.Ok(new { service = "clinical-trial-chat-api" }));
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));
app.MapGet("/api/health", () => Results.Ok(new { status = "healthy" }));
app.MapGet(
    "/api/runtime",
    () => Results.Ok(new
    {
        mode = useLocalDemo ? "local-demo" : "azure"
    }));
app.MapChatEndpoints();

app.Run();

public partial class Program;
