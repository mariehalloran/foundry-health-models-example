namespace ClinicalTrialChat.Api.Configuration;

public sealed record FoundryOptions(Uri Endpoint, string Deployment, int MaxOutputTokens)
{
    private const int DefaultMaxOutputTokens = 1_200;

    public static FoundryOptions FromConfiguration(IConfiguration configuration)
    {
        var endpointValue = configuration["AZURE_OPENAI_ENDPOINT"]
            ?? configuration["Foundry:Endpoint"];
        var deployment = configuration["AZURE_OPENAI_DEPLOYMENT"]
            ?? configuration["Foundry:Deployment"];
        var maxOutputTokensValue = configuration["Foundry:MaxOutputTokens"];

        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint)
            || endpoint.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException(
                "Set AZURE_OPENAI_ENDPOINT or Foundry:Endpoint to a valid HTTPS endpoint.");
        }

        if (string.IsNullOrWhiteSpace(deployment))
        {
            throw new InvalidOperationException(
                "Set AZURE_OPENAI_DEPLOYMENT or Foundry:Deployment.");
        }

        var maxOutputTokens = DefaultMaxOutputTokens;
        if (!string.IsNullOrWhiteSpace(maxOutputTokensValue)
            && (!int.TryParse(maxOutputTokensValue, out maxOutputTokens)
                || maxOutputTokens is < 100 or > 8_000))
        {
            throw new InvalidOperationException(
                "Foundry:MaxOutputTokens must be an integer from 100 through 8000.");
        }

        return new FoundryOptions(endpoint, deployment, maxOutputTokens);
    }
}
