namespace ClinicalTrialChat.Api.Models;

public static class DemoUserId
{
    private const string Prefix = "demo-";

    public static bool TryNormalize(string? value, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(value)
            || !value.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase)
            || !Guid.TryParseExact(value[Prefix.Length..], "D", out var id))
        {
            return false;
        }

        normalized = $"{Prefix}{id:D}";
        return true;
    }
}
