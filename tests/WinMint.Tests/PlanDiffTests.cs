using WinMint.Orchestrator;
using WinMint.Wizard;

namespace WinMint.Tests;

public class PlanDiffTests
{
    [Fact]
    public void Format_includes_offline_and_live_sections()
    {
        Profile profile = Lab();
        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);

        string text = PlanDiff.Format(planned.Value, profile);
        Assert.Contains("During image build", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("After first sign-in", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("MinGit", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Nilesoft", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Format_marks_product_constants_as_always()
    {
        Profile profile = Lab();
        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);

        string text = PlanDiff.Format(planned.Value, profile);
        Assert.Contains("always", text, StringComparison.Ordinal);
        Assert.Contains("OneDrive", text, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("MinGit", text, StringComparison.OrdinalIgnoreCase);
    }

    private static Profile Lab() =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
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
