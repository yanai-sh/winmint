using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PlanDiffTests
{
    [Fact]
    public void Sl7_host_review_empty_optional_packages_and_gate_b_on_release_strict()
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = Sl7SamplePassword.TryLoad();
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Code)));

        Assert.Equal("Yanai", parsed.Value.Account.Username);
        Assert.Empty(parsed.Value.WingetPackages);
        Assert.Empty(parsed.Value.WslDistros);
        Assert.Equal(AccountProfile.DefaultLocalPassword, parsed.Value.Account.Password);

        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(
            parsed.Value,
            new HostComposeOptions(
                ImageQuality: ImageQualityLane.Release,
                PackageStrict: PackageStrictOverride.Force));
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);

        HostReview review = planned.Value.Review;
        Assert.Empty(review.AuthoredProfile.WslDistros);
        Assert.Empty(review.AuthoredProfile.WingetPackages);
        Assert.DoesNotContain(
            review.EffectiveWsl,
            static id => id.Contains("FedoraLinux", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(
            review.EffectiveWinget,
            static id => id.Equals("Anysphere.Cursor", StringComparison.OrdinalIgnoreCase));
        Assert.True(review.PackageWireHonest);
        Assert.True(review.IsGateB);
    }

    [Fact]
    public void Host_review_projects_curated_package_facts_for_single_argument_diff()
    {
        Profile profile = Lab() with
        {
            WingetPackages = [ProductPosture.BraveWingetId, "Anysphere.Cursor"],
            ScoopPackages = ["curl"],
        };
        Result<BuildArtifacts, Failure> artifacts = BuildPlan.Plan(profile);
        Assert.True(artifacts.IsOk, artifacts.IsOk ? null : artifacts.Error.Message);
        Assert.True(artifacts.Value.BraveSelected);

        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);

        HostReview review = planned.Value.Review;
        Assert.True(review.BraveSelected);
        Assert.Contains("Anysphere.Cursor", review.EffectiveWinget);
        Assert.Contains("curl", review.EffectiveScoop);
        Assert.Empty(review.EffectiveWsl);

        string text = review.Diff;
        Assert.Contains("Brave policies — you chose", text, StringComparison.Ordinal);
        Assert.Contains("Winget Anysphere.Cursor — you chose", text, StringComparison.Ordinal);
        Assert.Contains("Scoop curl — you chose", text, StringComparison.Ordinal);
    }

    [Fact]
    public void BuildPlan_is_the_authority_for_Brave_selection()
    {
        Result<BuildArtifacts, Failure> artifacts = BuildPlan.Plan(Lab());
        Assert.True(artifacts.IsOk);
        Assert.False(artifacts.Value.BraveSelected);

        Result<HostPlan, HostComposeError> host = HostCompile.PlanDocument(Lab());
        Assert.True(host.IsOk);
        Assert.Equal(artifacts.Value.BraveSelected, host.Value.Review.BraveSelected);
    }

    [Fact]
    public void Format_online_appx_removals_are_after_sign_in_with_safety_net()
    {
        Profile profile = Lab();
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : planned.Error.Message);

        string text = planned.Value.Review.Diff;
        int duringBuild = text.IndexOf("During image build", StringComparison.OrdinalIgnoreCase);
        int afterSignIn = text.IndexOf("After first sign-in", StringComparison.OrdinalIgnoreCase);
        int safetyNet = text.IndexOf("AppX safety net — always", StringComparison.OrdinalIgnoreCase);
        int bingNews = text.IndexOf("Microsoft.BingNews", StringComparison.OrdinalIgnoreCase);

        // Offline RemoveProvisionedAppx lists AppX during build; Online also keeps safety-net after sign-in.
        Assert.True(duringBuild >= 0 && duringBuild < bingNews);
        Assert.True(bingNews < afterSignIn);
        Assert.True(afterSignIn < safetyNet);
        Assert.Contains("AppX safety net — always", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Format_offline_appx_removals_are_during_image_build()
    {
        Profile profile = Lab() with { DebloatMode = DebloatMode.Offline };
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(profile);
        Assert.True(planned.IsOk);

        string text = planned.Value.Review.Diff;
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
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(profile);
        Assert.True(planned.IsOk);

        string text = planned.Value.Review.Diff;

        Assert.Contains("Winget Git.Git — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Microsoft.PowerShell — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Microsoft.WindowsTerminal — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Nilesoft.Shell — always", text, StringComparison.Ordinal);
        Assert.Contains("Winget Anysphere.Cursor — you chose", text, StringComparison.Ordinal);
        Assert.Contains("Scoop starship — always", text, StringComparison.Ordinal);
        Assert.DoesNotContain("Winget import", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Format_uses_effective_facts_without_generated_package_json()
    {
        Profile profile = Lab() with { WingetPackages = ["Anysphere.Cursor"] };
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(profile);
        Assert.True(planned.IsOk);

        string text = planned.Value.Review.Diff;

        Assert.Contains("Winget Git.Git — always", text, StringComparison.Ordinal);
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
        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(profile);
        Assert.True(planned.IsOk);
        HostReview review = planned.Value.Review with
        {
            Jobs = [new ProvisionJob("missing.package", kind, PackageId: "Missing.Package")],
            EffectivePackages = [],
            PackageWireHonest = false,
        };

        string text = review.Diff;

        Assert.Contains(expected, text, StringComparison.Ordinal);
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
