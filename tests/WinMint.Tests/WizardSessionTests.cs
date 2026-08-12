using WinMint.Orchestrator;
using WinMint.Wizard;

namespace WinMint.Tests;

public class WizardSessionTests
{
    private static WizardSessionInput Lab(
        string preset = DebloatPresets.Recommended,
        string winget = "",
        string appx = "",
        string caps = "",
        string iso = @"C:\isos\Win11.iso",
        string lane = "Test",
        string locale = "en-GB",
        string geoId = "242",
        string timeZone = "GMT Standard Time") =>
        new(
            preset,
            "winmint",
            "lab-only",
            RequireWifiDuringOobe: false,
            DmaEnabled: true,
            Locale: locale,
            GeoIdText: geoId,
            TimeZoneId: timeZone,
            LocationServicesEnabled: true,
            WingetText: winget,
            RemoveCapabilitiesText: caps,
            RemoveProvisionedAppxText: appx,
            SourceIsoPath: iso,
            ImageQualityText: lane);

    [Fact]
    public void ComposeAndPlan_recommended_default_expands_debloat()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(Lab());
        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("Microsoft.YourPhone", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Microsoft.GamingApp", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Copilot", result.ProfileJson!, StringComparison.Ordinal);
        Assert.DoesNotContain("recommended", result.ProfileJson!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"keepCopilot\"", result.ProfileJson!, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_always_unions_product_required_appx()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(Lab(preset: DebloatPresets.Empty));
        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("Microsoft.GamingApp", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Copilot", result.ProfileJson!, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_host_dma_settle_fields_round_trip()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(
            Lab(locale: "en-US", geoId: "117", timeZone: "Israel Standard Time"));
        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("\"locale\": \"en-US\"", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("\"geoId\": 117", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Israel Standard Time", result.ProfileJson!, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_acceptance_ok()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(Lab(preset: DebloatPresets.Acceptance));
        Assert.True(result.Succeeded, result.Message);
        Assert.NotNull(result.ProfileUtf8);
        Assert.Contains("Microsoft.BingNews", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Lane=Test", result.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_release_lane_in_summary()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(Lab(lane: "Release"));
        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("Lane=Release", result.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_appx_override_replaces_preset()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(Lab(appx: "Microsoft.GetHelp"));
        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("Microsoft.GetHelp", result.ProfileJson!, StringComparison.Ordinal);
        Assert.DoesNotContain("Microsoft.BingNews", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Copilot", result.ProfileJson!, StringComparison.Ordinal);
        Assert.Contains("Microsoft.GamingApp", result.ProfileJson!, StringComparison.Ordinal);
    }

    [Fact]
    public void ComposeAndPlan_advanced_winget_overrides_chip_resolution()
    {
        WizardSessionResult result = WizardSession.ComposeAndPlan(
            Lab(winget: "jqlang.jq"));
        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("jqlang.jq", result.ProfileJson!, StringComparison.Ordinal);
        Assert.DoesNotContain("Anysphere.Cursor", result.ProfileJson!, StringComparison.Ordinal);
    }

    [Fact]
    public void ResolvePackageChips_zen_and_cursor_emit_catalog_install_ids()
    {
        Result<PackageSelection, Failure> selection = WizardSession.ResolvePackageChips(
            ["zen-browser"],
            ["cursor"],
            [],
            ["FedoraLinux"]);
        Assert.True(selection.IsOk);
        Assert.Contains("Zen-Team.Zen-Browser", selection.Value.WingetInstallIds);
        Assert.Contains("Anysphere.Cursor", selection.Value.WingetInstallIds);
        Assert.Equal("FedoraLinux", Assert.Single(selection.Value.WslProfileTokens));
    }

    [Fact]
    public void MergeChipAndAdvanced_advanced_wins()
    {
        string merged = WizardSession.MergeChipAndAdvanced(["a", "b"], "c\nd");
        Assert.Equal($"c{Environment.NewLine}d", merged);
    }

    [Fact]
    public void MergeChipAndAdvanced_chips_when_advanced_empty()
    {
        string merged = WizardSession.MergeChipAndAdvanced(["Git.Git", "jqlang.jq"], "  \n ");
        Assert.Equal($"Git.Git{Environment.NewLine}jqlang.jq", merged);
    }

    [Fact]
    public void FormatBuildRecipe_includes_lane_and_optional_wim()
    {
        string recipe = WizardSession.FormatBuildRecipe(
            @"D:\out\winmint.profile.json",
            @"E:\Win11.iso",
            "Release",
            wimIndex: 5);
        Assert.Contains("--image-quality Release", recipe, StringComparison.Ordinal);
        Assert.Contains("--package-strict", recipe, StringComparison.Ordinal);
        Assert.Contains("%LOCALAPPDATA%\\WinMint\\work\\gate-b", recipe, StringComparison.Ordinal);
        Assert.Contains("--wim-index 5", recipe, StringComparison.Ordinal);
        Assert.Contains("--iso \"E:\\Win11.iso\"", recipe, StringComparison.Ordinal);
        Assert.StartsWith("winmint build ", recipe, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatBuildRecipe_test_uses_programdata_without_package_strict()
    {
        string recipe = WizardSession.FormatBuildRecipe(
            @"D:\p.json",
            @"E:\a.iso",
            "Test",
            ImageServicing.DefaultProWimIndex);
        Assert.Contains("%ProgramData%\\WinMint\\work", recipe, StringComparison.Ordinal);
        Assert.DoesNotContain("--package-strict", recipe, StringComparison.Ordinal);
        Assert.DoesNotContain("gate-b", recipe, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatBuildRecipe_omits_pro_wim_index()
    {
        string recipe = WizardSession.FormatBuildRecipe(
            @"D:\p.json",
            @"E:\a.iso",
            "Test",
            ImageServicing.DefaultProWimIndex);
        Assert.DoesNotContain("--wim-index", recipe, StringComparison.Ordinal);
    }

    [Fact]
    public void ResolveWorkDirectory_release_defaults_to_gate_b()
    {
        Assert.Equal(
            HostDefaults.GateBWorkDirectory,
            WizardBuild.GateBWorkDirectory);
        Assert.Equal(
            HostDefaults.DefaultWorkDirectory,
            WizardBuild.DefaultWorkDirectory);
        Assert.Equal(
            WizardBuild.GateBWorkDirectory,
            WizardBuild.ResolveWorkDirectory(ImageQualityLane.Release));
        Assert.Equal(
            WizardBuild.DefaultWorkDirectory,
            WizardBuild.ResolveWorkDirectory(ImageQualityLane.Test));
    }

    [Fact]
    public void FormatBuildRecipe_emits_home_wim_index()
    {
        string recipe = WizardSession.FormatBuildRecipe(
            @"D:\p.json",
            @"E:\a.iso",
            "Test",
            BuildMachineEdition.HomeWimIndex);
        Assert.Contains("--wim-index 1", recipe, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("Professional", ImageServicing.DefaultProWimIndex)]
    [InlineData("ProfessionalN", ImageServicing.DefaultProWimIndex)]
    [InlineData("ProfessionalWorkstation", ImageServicing.DefaultProWimIndex)]
    [InlineData("Core", BuildMachineEdition.HomeWimIndex)]
    [InlineData("CoreN", BuildMachineEdition.HomeWimIndex)]
    [InlineData("Home", BuildMachineEdition.HomeWimIndex)]
    [InlineData(null, BuildMachineEdition.HomeWimIndex)]
    [InlineData("", BuildMachineEdition.HomeWimIndex)]
    public void DefaultWimIndex_follows_host_edition(string? editionId, int expected) =>
        Assert.Equal(expected, BuildMachineEdition.DefaultWimIndexForEditionId(editionId));
}
