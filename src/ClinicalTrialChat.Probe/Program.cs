using Azure.Identity;

namespace ClinicalTrialChat.Probe;

internal static class ProbeProgram
{
    public static async Task<int> Main()
    {
        var options = ProbeOptions.FromEnvironment();
        var credential = new ManagedIdentityCredential(
            ManagedIdentityId.FromUserAssignedClientId(
                options.ManagedIdentityClientId));
        using var httpClient = new HttpClient
        {
            Timeout = Timeout.InfiniteTimeSpan
        };
        var probe = new FoundryAvailabilityProbe(
            httpClient,
            credential,
            options);
        using var timeout = new CancellationTokenSource(options.Timeout);

        try
        {
            var result = await probe.ExecuteAsync(timeout.Token);
            Console.WriteLine(
                "Foundry synthetic probe succeeded in {0} ms. Request ID: {1}.",
                Math.Round(result.Duration.TotalMilliseconds),
                result.RequestId ?? "unavailable");
            return 0;
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            Console.Error.WriteLine(
                "Foundry synthetic probe exceeded its {0}-second timeout.",
                options.Timeout.TotalSeconds);
            return 1;
        }
    }
}
