namespace ClinicalTrialChat.Api.Tests;

public sealed class FrontendFilesTests
{
    private static readonly string FrontendPath = Path.GetFullPath(
        Path.Combine(
            AppContext.BaseDirectory,
            "..",
            "..",
            "..",
            "..",
            "..",
            "src",
            "ClinicalTrialChat.Web"));

    [Fact]
    public void StaticFrontend_HasRequiredEntryPoints()
    {
        var index = File.ReadAllText(Path.Combine(FrontendPath, "index.html"));
        var app = File.ReadAllText(Path.Combine(FrontendPath, "app.js"));
        var staticWebAppConfig = File.ReadAllText(
            Path.Combine(FrontendPath, "staticwebapp.config.json"));

        Assert.Contains("TrialGuide", index, StringComparison.Ordinal);
        Assert.Contains("type=\"module\"", index, StringComparison.Ordinal);
        Assert.Contains("http://localhost:5228", app, StringComparison.Ordinal);
        Assert.Contains("\"/api/*\"", staticWebAppConfig, StringComparison.Ordinal);
    }
}
