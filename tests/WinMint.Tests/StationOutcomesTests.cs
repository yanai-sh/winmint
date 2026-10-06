using System.Text;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class StationOutcomesTests
{
    [Fact]
    public void Minimal_seeds_empty_software_and_windows_taskbar()
    {
        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(StationOutcomes.Minimal);
        Assert.True(seed.IsOk);
        Assert.Empty(seed.Value.ToolChipKeys);
        Assert.Empty(seed.Value.WslTokens);
        Assert.Empty(seed.Value.Packages.WingetInstallIds);
        Assert.Empty(seed.Value.Packages.WslProfileTokens);
        Assert.Empty(seed.Value.RemoveProvisionedAppx);
        Assert.Equal(StationOutcomes.TaskbarWindows, seed.Value.TaskbarSurface);
        Assert.False(seed.Value.Komorebi);
        Assert.Contains("Windows taskbar", seed.Value.SelectionLabels);
    }

    [Fact]
    public void Comfort_seeds_recommended_debloat_and_curated_packages()
    {
        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(StationOutcomes.Comfort);
        Assert.True(seed.IsOk, seed.IsOk ? null : seed.Error.Message);

        Result<DebloatExpansion, Failure> recommended =
            DebloatPresets.TryExpand(DebloatPresets.Recommended);
        Assert.True(recommended.IsOk);
        Assert.Equal(recommended.Value.RemoveProvisionedAppx, seed.Value.RemoveProvisionedAppx);
        Assert.Equal(recommended.Value.RemoveCapabilities, seed.Value.RemoveCapabilities);
        Assert.Equal(recommended.Value.DisableOptionalFeatures, seed.Value.DisableOptionalFeatures);

        Assert.Equal(["cursor", "zen-browser"], seed.Value.ToolChipKeys);
        Assert.Equal(["FedoraLinux"], seed.Value.WslTokens);
        Assert.Equal(["Anysphere.Cursor", "Zen-Team.Zen-Browser"], seed.Value.Packages.WingetInstallIds);
        Assert.Equal(["FedoraLinux"], seed.Value.Packages.WslProfileTokens);
        Assert.Equal(StationOutcomes.TaskbarWindows, seed.Value.TaskbarSurface);
        Assert.False(seed.Value.Komorebi);
        Assert.Equal(
            ["Windows taskbar", "Cursor", "Zen", "Fedora 44"],
            seed.Value.SelectionLabels);
    }

    [Fact]
    public void Power_seeds_komorebi_axis_and_denser_editor_chips()
    {
        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(StationOutcomes.Power);
        Assert.True(seed.IsOk, seed.IsOk ? null : seed.Error.Message);
        Assert.Contains("neovim", seed.Value.ToolChipKeys);
        Assert.Contains("vscode", seed.Value.ToolChipKeys);
        Assert.Equal(["FedoraLinux"], seed.Value.WslTokens);
        Assert.True(seed.Value.Komorebi);
        Assert.Equal(StationOutcomes.TaskbarWindows, seed.Value.TaskbarSurface);
        Assert.Contains("LGUG2Z.komorebi", seed.Value.Packages.WingetInstallIds);
        Assert.Contains("LGUG2Z.whkd", seed.Value.Packages.WingetInstallIds);
        Assert.Contains("Komorebi", seed.Value.SelectionLabels);
        Assert.Contains("Neovim", seed.Value.SelectionLabels);
        Assert.Contains("VS Code", seed.Value.SelectionLabels);
    }

    [Fact]
    public void Seed_unknown_fails()
    {
        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed("lane");
        Assert.False(seed.IsOk);
        Assert.Equal("station.outcome.unknown", seed.Error.Code);
    }

    [Fact]
    public void Serialized_profile_never_contains_outcome_names()
    {
        foreach (string outcome in new[] { StationOutcomes.Minimal, StationOutcomes.Comfort, StationOutcomes.Power })
        {
            Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(outcome);
            Assert.True(seed.IsOk);

            Profile profile = new(
                new AccountProfile("winmint", "lab-only", false),
                new DmaProfile(true, new DmaSettleTarget("he-IL", 117, "Israel Standard Time", true)),
                DebloatMode.Online,
                seed.Value.RemoveProvisionedAppx,
                seed.Value.Packages.WingetInstallIds,
                [],
                seed.Value.Packages.ScoopInstallIds,
                [],
                seed.Value.Packages.WslProfileTokens,
                [],
                seed.Value.RemoveCapabilities,
                seed.Value.DisableOptionalFeatures);

            string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(profile));
            Assert.DoesNotContain("\"minimal\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"comfort\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"power\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"recommended\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"station\"", json, StringComparison.OrdinalIgnoreCase);
        }
    }
}
