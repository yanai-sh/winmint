using WinMint.Orchestrator;
using WinMint.Contracts;
using WinMint.Wizard;

namespace WinMint.Tests;

public class PlanDiffTests
{
    [Fact]
    public void Format_online_appx_removals_are_after_sign_in_with_safety_net()
    {
        Profile profile = Lab();
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);

        string text = PlanDiff.Format(planned.Value, profile);
        int duringBuild = text.IndexOf("During image build", StringComparison.OrdinalIgnoreCase);
        int afterSignIn = text.IndexOf("After first sign-in", StringComparison.OrdinalIgnoreCase);
        int safetyNet = text.IndexOf("AppX safety net — always", StringComparison.OrdinalIgnoreCase);
        int bingNews = text.IndexOf("Microsoft.BingNews", StringComparison.OrdinalIgnoreCase);

        Assert.True(duringBuild < afterSignIn);
        Assert.True(afterSignIn < safetyNet);
        Assert.True(safetyNet < bingNews);
    }

    [Fact]
    public void Format_offline_appx_removals_are_during_image_build()
    {
        Profile profile = Lab() with { DebloatMode = DebloatMode.Offline };
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);

        string text = PlanDiff.Format(planned.Value, profile);
        int duringBuild = text.IndexOf("During image build", StringComparison.OrdinalIgnoreCase);
        int afterSignIn = text.IndexOf("After first sign-in", StringComparison.OrdinalIgnoreCase);
        int bingNews = text.IndexOf("Microsoft.BingNews", StringComparison.OrdinalIgnoreCase);

        Assert.True(duringBuild < bingNews);
        Assert.True(bingNews < afterSignIn);
        Assert.DoesNotContain("AppX safety net", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Format_expands_winget_import_and_marks_constants()
    {
        Profile profile = Lab() with { WingetPackages = ["Anysphere.Cursor"] };
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);

        string text = PlanDiff.Format(planned.Value, profile);

        Assert.Contains("Winget Git.MinGit — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Microsoft.PowerShell — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Microsoft.WindowsTerminal — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Nilesoft.Shell — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Anysphere.Cursor — you chose", text, StringComparison.Ordinal);
        Assert.Contains("Scoop starship — always", text, StringComparison.Ordinal);
        Assert.DoesNotContain("Winget import", text, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("not-json")]
    public void Format_uses_effective_facts_when_import_json_is_unavailable(string? importJson)
    {
        Profile profile = Lab() with { WingetPackages = ["Anysphere.Cursor"] };
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        BuildArtifacts artifacts = planned.Value with
        {
            WingetImportJson = importJson is null ? null : System.Text.Encoding.UTF8.GetBytes(importJson),
        };

        string text = PlanDiff.Format(artifacts, profile);

        Assert.Contains("Winget Git.MinGit — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Anysphere.Cursor — you chose", text, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(ProvisionJobKind.Winget, "Winget Missing.Package — you chose")]
    [InlineData(ProvisionJobKind.Wsl, "WSL Missing.Package — you chose")]
    public void Format_falls_back_to_job_label_when_per_job_package_fact_is_missing(
        ProvisionJobKind kind,
        string expected)
    {
        Profile profile = Lab();
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);
        BuildArtifacts artifacts = planned.Value with
        {
            Jobs = new JobsArtifact(
                planned.Value.Jobs.SchemaVersion,
                [new ProvisionJob("missing.package", kind, PackageId: "Missing.Package")]),
            EffectivePackages = [],
        };

        string text = PlanDiff.Format(artifacts, profile);

        Assert.Contains(expected, text, StringComparison.Ordinal);
    }

    private static Profile Lab() =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            ["Microsoft.BingNews"],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);
}
