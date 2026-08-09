using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class WingetImportTests
{
    [Fact]
    public void Plan_arm64_winget_emits_import_job_and_json_not_per_id_jobs()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor", "jqlang.jq"]);
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk);
        Assert.NotNull(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "winget.import");
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "winget");
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "package.auditNative");
    }

    [Fact]
    public void Plan_non_arm64_emits_individual_winget_jobs()
    {
        Profile profile = LabProfile(winget: ["Git.Git"]);
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "amd64" });

        Assert.True(result.IsOk);
        Assert.Null(result.Value.WingetImportJson);
        Assert.Contains(result.Value.Jobs.Jobs, j => j is { Kind: "winget", PackageId: "Git.Git" });
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "winget.import");
    }

    [Fact]
    public void Import_json_includes_arm64_override_arguments()
    {
        byte[] json = WingetImportBuilder.BuildUtf8Json(
            ["Anysphere.Cursor"],
            PackageCatalog.Default,
            "arm64");
        using JsonDocument doc = JsonDocument.Parse(json);
        JsonElement pkg = doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages")[0];
        Assert.Equal("Anysphere.Cursor", pkg.GetProperty("PackageIdentifier").GetString());
        Assert.Equal("--architecture arm64", pkg.GetProperty("InitialOverrideArguments").GetString());
    }

    private static Profile LabProfile(IReadOnlyList<string> winget) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            winget,
            [],
            [],
            [],
            [],
            [],
            [],
            []);
}
