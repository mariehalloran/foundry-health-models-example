using ClinicalTrialChat.Api.Models;

namespace ClinicalTrialChat.Api.Services;

public interface IStarterQuestionProvider
{
    IReadOnlyList<StarterQuestion> Questions { get; }
}
