using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ProductRequiredStripTests
{
    [Fact]
    public void Union_adds_copilot_and_gaming_when_missing()
    {
        IReadOnlyList<string> merged = ProductRequiredStrip.UnionAppx(["Microsoft.BingNews"]);

        Assert.Contains("Microsoft.Copilot", merged);
        Assert.Contains("Microsoft.GamingApp", merged);
        Assert.Contains("Microsoft.Xbox.TCUI", merged);
        Assert.Contains("Microsoft.XboxGamingOverlay", merged);
        Assert.Contains("Microsoft.XboxSpeechToTextOverlay", merged);
        Assert.Contains("Microsoft.BingNews", merged);
    }

    [Fact]
    public void Union_deduplicates_case_insensitively()
    {
        IReadOnlyList<string> merged = ProductRequiredStrip.UnionAppx(
            ["Microsoft.Copilot", "microsoft.gamingapp"]);

        Assert.Equal(1, merged.Count(id => string.Equals(id, "Microsoft.Copilot", StringComparison.OrdinalIgnoreCase)));
        Assert.Equal(1, merged.Count(id => string.Equals(id, "Microsoft.GamingApp", StringComparison.OrdinalIgnoreCase)));
    }

    [Fact]
    public void Plan_never_stamps_copilot_kill_policies()
    {
        Profile profile = Lab(new PoliciesProfile(KeepCopilot: false));

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);

        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        string specs = Assert.Single(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.StampOfflinePolicies).Parameters[StageParams.PolicySpecs];
        Assert.DoesNotContain("TurnOffWindowsCopilot", specs, StringComparison.Ordinal);
        Assert.DoesNotContain("HubsSidebarEnabled", specs, StringComparison.Ordinal);
    }

    private static Profile Lab(PoliciesProfile policies) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            policies);
}
