using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Contracts;
using WinMint.Wizard;

namespace WinMint.Tests;

/// <summary>#90 plan/build honesty — S1 BuildPlan file/honesty helpers; S1b WizardSession summary.</summary>
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
    public void SerializeJobsFile_includes_scoopBuckets()
    {
        string json = BuildPlan.SerializeJobsFile(
            new JobsArtifact(
                BuildPlan.JobsSchemaVersion,
                [
                    new ProvisionJob(
                        "scoop.batch",
                        ProvisionJobKind.ScoopBatch,
                        PackageId: "curl komorebi",
                        ScoopBuckets: ["extras", "main"]),
                ]));

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

    [Fact]
    public void ComposeAndPlan_summary_surfaces_network_honesty()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(
            new WizardSessionInput(
                DebloatPresets.Empty,
                "winmint",
                "lab-only",
                RequireWifiDuringOobe: true,
                DmaEnabled: true,
                Locale: "en-GB",
                GeoIdText: "242",
                TimeZoneId: "GMT Standard Time",
                LocationServicesEnabled: true,
                WingetText: "jqlang.jq",
                SourceIsoPath: @"C:\isos\Win11.iso",
                ImageQualityText: "Test"));

        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("requiresNetwork=true", result.Message, StringComparison.Ordinal);
        Assert.Contains("requireWifiDuringOobe=true", result.Message, StringComparison.Ordinal);
        Assert.Contains("Warning:", result.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_network_warning_does_not_fail_plan()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(
            new WizardSessionInput(
                DebloatPresets.Empty,
                "winmint",
                "lab-only",
                RequireWifiDuringOobe: false,
                DmaEnabled: true,
                Locale: "en-GB",
                GeoIdText: "242",
                TimeZoneId: "GMT Standard Time",
                LocationServicesEnabled: true,
                WingetText: "jqlang.jq",
                SourceIsoPath: @"C:\isos\Win11.iso"));

        Assert.True(result.Succeeded, result.Message);
        Assert.NotNull(result.ProfileUtf8);
        Assert.True(Encoding.UTF8.GetString(result.ProfileUtf8!).Length > 0);
    }
}
