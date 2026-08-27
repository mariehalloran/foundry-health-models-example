namespace ClinicalTrialChat.Probe;

internal sealed record ProbeOptions(
    Uri Endpoint,
    string Deployment,
    string ManagedIdentityClientId,
    TimeSpan Timeout)
{
    private const int DefaultTimeoutSeconds = 45;

    public static ProbeOptions FromEnvironment() =>
        FromValues(Environment.GetEnvironmentVariable);

    internal static ProbeOptions FromValues(Func<string, string?> valueProvider)
    {
        ArgumentNullException.ThrowIfNull(valueProvider);

        var endpointValue = valueProvider("AZURE_OPENAI_ENDPOINT");
        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint)
            || endpoint.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidOperationException(
                "Set AZURE_OPENAI_ENDPOINT to a valid HTTPS endpoint.");
        }

        var deployment = valueProvider("AZURE_OPENAI_DEPLOYMENT");
        if (string.IsNullOrWhiteSpace(deployment))
        {
            throw new InvalidOperationException(
                "Set AZURE_OPENAI_DEPLOYMENT to the model deployment name.");
        }

        var clientId = valueProvider("AZURE_CLIENT_ID");
        if (!Guid.TryParse(clientId, out _))
        {
            throw new InvalidOperationException(
                "Set AZURE_CLIENT_ID to the probe managed identity client ID.");
        }

        var timeoutSeconds = DefaultTimeoutSeconds;
        var timeoutValue = valueProvider("PROBE_TIMEOUT_SECONDS");
        if (!string.IsNullOrWhiteSpace(timeoutValue)
            && (!int.TryParse(timeoutValue, out timeoutSeconds)
                || timeoutSeconds is < 5 or > 50))
        {
            throw new InvalidOperationException(
                "PROBE_TIMEOUT_SECONDS must be an integer from 5 through 50.");
        }

        return new ProbeOptions(
            endpoint,
            deployment.Trim(),
            clientId,
            TimeSpan.FromSeconds(timeoutSeconds));
    }
}
