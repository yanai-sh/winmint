using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Contracts;

namespace WinMint.Tests;

/// <summary>#90 plan/build honesty — S1 BuildPlan file/honesty helpers.</summary>
public class PlanHonestyTests
{
    [Fact]
    public void SerializeManifestFile_includes_requiresNetwork()
    {
        string json = BuildPlan.SerializeManifestFile(
            new BuildManifest(ImageQualityLane.Test, RequiresNetwork: true));

        using JsonDocument doc = JsonDocument.Parse(json);
        Assert.Equal("Test", doc.RootElement.GetProperty("imageQuality").GetString());
        Assert.True(doc.RootElement.GetProperty("requiresNetwork").GetBoolean());
    }

    [Fact]
    public void JobsWire_includes_scoopBuckets()
    {
        string json = JobsWire.Write(
            [
                new ProvisionJob(
                    "scoop.batch",
                    ProvisionJobKind.ScoopBatch,
                    PackageId: "curl komorebi",
                    ScoopBuckets: ["extras", "main"]),
            ]);

        using JsonDocument doc = JsonDocument.Parse(json);
        JsonElement job = doc.RootElement.GetProperty("jobs")[0];
        Assert.Equal("scoop.batch", job.GetProperty("kind").GetString());
        Assert.Equal(
            ["extras", "main"],
            job.GetProperty("scoopBuckets").EnumerateArray().Select(e => e.GetString()!).ToArray());
    }

    [Fact]
    public void FormatPlanHonesty_warns_when_requires_network()
    {
        string text = BuildPlan.FormatPlanHonesty(
            new BuildManifest(ImageQualityLane.Release, RequiresNetwork: true),
            requireWifiDuringOobe: true);

        Assert.Contains("requiresNetwork=true", text, StringComparison.Ordinal);
        Assert.Contains("requireWifiDuringOobe=true", text, StringComparison.Ordinal);
        Assert.Contains("OOBE may show Network", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Warning:", text, StringComparison.Ordinal);
        Assert.Contains("outbound network", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void FormatPlanHonesty_quiet_when_no_network_needed()
    {
        string text = BuildPlan.FormatPlanHonesty(
            new BuildManifest(ImageQualityLane.Test, RequiresNetwork: false),
            requireWifiDuringOobe: false);

        Assert.Contains("requiresNetwork=false", text, StringComparison.Ordinal);
        Assert.Contains("requireWifiDuringOobe=false", text, StringComparison.Ordinal);
        Assert.Contains("Network page hidden", text, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Warning:", text, StringComparison.Ordinal);
    }

}
