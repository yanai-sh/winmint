using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class WingetImportTests
{
    [Fact]
    public void Plan_arm64_winget_emits_import_job_and_json_not_per_id_jobs()
    {
        Profile profile = LabProfile(winget: ["Anysphere.Cursor", "jqlang.jq"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
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
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
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
        Profile profile = LabProfile(winget: ["Anysphere.Cursor"]);
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk);
        Assert.NotNull(result.Value.WingetImportJson);
        using JsonDocument doc = JsonDocument.Parse(result.Value.WingetImportJson);
        JsonElement packages = doc.RootElement.GetProperty("Sources")[0].GetProperty("Packages");
        Assert.Contains(
            packages.EnumerateArray(),
            pkg => pkg.GetProperty("PackageIdentifier").GetString() == "Anysphere.Cursor"
                && pkg.GetProperty("InitialOverrideArguments").GetString() == "--architecture arm64");
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
