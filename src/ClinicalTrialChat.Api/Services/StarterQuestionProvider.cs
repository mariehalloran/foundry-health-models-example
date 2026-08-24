using System.Text.Json;
using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public sealed class StarterQuestionProvider : IStarterQuestionProvider
{
    public StarterQuestionProvider(IWebHostEnvironment environment)
    {
        var path = Path.Combine(
            environment.ContentRootPath,
            "Data",
            "sample-questions.json");

        if (!File.Exists(path))
        {
            throw new InvalidOperationException(
                $"The starter-question file was not found at '{path}'.");
        }

        var json = File.ReadAllText(path);
        Questions = JsonSerializer.Deserialize<List<StarterQuestion>>(
                json,
                new JsonSerializerOptions(JsonSerializerDefaults.Web))
            ?? throw new InvalidOperationException(
                "The starter-question file did not contain a JSON array.");

        if (Questions.Count == 0
            || Questions.Any(question =>
                string.IsNullOrWhiteSpace(question.Id)
                || string.IsNullOrWhiteSpace(question.Text)))
        {
            throw new InvalidOperationException(
                "Every starter question must have a non-empty id and text.");
        }
    }

    public IReadOnlyList<StarterQuestion> Questions { get; }
}
