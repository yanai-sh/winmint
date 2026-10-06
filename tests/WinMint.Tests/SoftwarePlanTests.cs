using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>#147 — SoftwarePlan owns package plan + HostReview package facts (not a pass-through).</summary>
public class SoftwarePlanTests
{
    [Fact]
    public void TryPlan_returns_review_package_facts_host_review_projects()
    {
        Profile profile = Lab() with
        {
            WingetPackages = ["Anysphere.Cursor"],
            ScoopPackages = ["curl"],
            WslDistros = ["FedoraLinux"],
        };

        Result<PackagePlanSlice, Failure> planned = SoftwarePlan.TryPlan(
            profile,
            PackageCatalog.Default,
            "arm64",
            auditStrict: false);
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);

        PackagePlanSlice slice = planned.Value;
        Assert.Contains("Anysphere.Cursor", slice.EffectiveWinget);
        Assert.Contains(ProductPosture.MinGitWingetId, slice.EffectiveWinget);
        Assert.Contains("curl", slice.EffectiveScoop);
        Assert.Contains("FedoraLinux-44", slice.EffectiveWsl);
        Assert.True(slice.PackageWireHonest);
        Assert.Contains(
            slice.Jobs,
            static job => job.Kind == ProvisionJobKind.Wsl && job.PackageId == "FedoraLinux-44");

        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(
            profile,
            new HostComposeOptions(
                ImageQuality: ImageQualityLane.Release,
                PackageStrict: PackageStrictOverride.Force));
        Assert.True(host.IsOk, host.IsOk ? null : host.Error.Message);

        HostReview review = host.Value.Review;
        Assert.Equal(slice.EffectiveWinget, review.EffectiveWinget);
        Assert.Equal(slice.EffectiveScoop, review.EffectiveScoop);
        Assert.Equal(slice.EffectiveWsl, review.EffectiveWsl);
        Assert.Equal(slice.PackageWireHonest, review.PackageWireHonest);
        Assert.True(review.IsGateB);
    }

    private static Profile Lab() =>
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
            []);
}
