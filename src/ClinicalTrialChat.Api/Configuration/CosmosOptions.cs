namespace ClinicalTrialChat.Api.Configuration;

public sealed record CosmosOptions(Uri Endpoint, string Database, string Container)
{
    public static CosmosOptions FromConfiguration(IConfiguration configuration)
    {
        var endpointValue = configuration["COSMOS_ENDPOINT"]
            ?? configuration["Cosmos:Endpoint"];
        var database = configuration["COSMOS_DATABASE"]
            ?? configuration["Cosmos:Database"];
        var container = configuration["COSMOS_CONTAINER"]
            ?? configuration["Cosmos:Container"];

        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint)
            || endpoint.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException(
                "Set COSMOS_ENDPOINT or Cosmos:Endpoint to a valid HTTPS endpoint.");
        }

        if (string.IsNullOrWhiteSpace(database))
        {
            throw new InvalidOperationException("Set COSMOS_DATABASE or Cosmos:Database.");
        }

        if (string.IsNullOrWhiteSpace(container))
        {
            throw new InvalidOperationException("Set COSMOS_CONTAINER or Cosmos:Container.");
        }

        return new CosmosOptions(endpoint, database, container);
    }
}
