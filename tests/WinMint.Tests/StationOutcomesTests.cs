using System.Text;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class StationOutcomesTests
{
    [Fact]
    public void Minimal_expands_to_empty_debloat_and_no_chips()
    {
        Result<StationOutcomeExpansion, Failure> expanded = StationOutcomes.TryExpand(StationOutcomes.Minimal);
        Assert.True(expanded.IsOk);
        Assert.Equal(DebloatPresets.Empty, expanded.Value.DebloatPreset);
        Assert.Empty(expanded.Value.ToolChipKeys);
        Assert.Empty(expanded.Value.WslTokens);
        Assert.False(expanded.Value.Komorebi);
    }

    [Fact]
    public void Comfort_matches_CuratedDefaults_seed()
    {
        Result<StationOutcomeExpansion, Failure> expanded = StationOutcomes.TryExpand(StationOutcomes.Comfort);
        Assert.True(expanded.IsOk);
        Assert.Equal(DebloatPresets.Recommended, expanded.Value.DebloatPreset);
        Assert.Equal(CuratedDefaults.ToolChipKeys, expanded.Value.ToolChipKeys);
        Assert.Equal(CuratedDefaults.WslTokens, expanded.Value.WslTokens);
        Assert.False(expanded.Value.Komorebi);
    }

    [Fact]
    public void Power_adds_komorebi_and_denser_editor_chips()
    {
        Result<StationOutcomeExpansion, Failure> expanded = StationOutcomes.TryExpand(StationOutcomes.Power);
        Assert.True(expanded.IsOk);
        Assert.Equal(DebloatPresets.Recommended, expanded.Value.DebloatPreset);
        Assert.Equal(StationOutcomes.PowerToolChipKeys, expanded.Value.ToolChipKeys);
        Assert.Contains("neovim", expanded.Value.ToolChipKeys);
        Assert.Contains("vscode", expanded.Value.ToolChipKeys);
        Assert.Equal(CuratedDefaults.WslTokens, expanded.Value.WslTokens);
        Assert.True(expanded.Value.Komorebi);

        Result<PackageSelection, Failure> tools =
            PackageCatalog.Default.ResolveToolKeys(expanded.Value.ToolChipKeys);
        Assert.True(tools.IsOk, tools.IsOk ? null : tools.Error.Message);
    }

    [Fact]
    public void Expand_unknown_fails()
    {
        Result<StationOutcomeExpansion, Failure> expanded = StationOutcomes.TryExpand("lane");
        Assert.False(expanded.IsOk);
        Assert.Equal("station.outcome.unknown", expanded.Error.Code);
    }

    [Fact]
    public void Serialized_profile_never_contains_outcome_names()
    {
        foreach (string outcome in new[] { StationOutcomes.Minimal, StationOutcomes.Comfort, StationOutcomes.Power })
        {
            Result<StationOutcomeExpansion, Failure> seed = StationOutcomes.TryExpand(outcome);
            Assert.True(seed.IsOk);
            Result<DebloatExpansion, Failure> debloat = DebloatPresets.TryExpand(seed.Value.DebloatPreset);
            Assert.True(debloat.IsOk);
            Result<PackageSelection, Failure> tools =
                PackageCatalog.Default.ResolveToolKeys(seed.Value.ToolChipKeys);
            Assert.True(tools.IsOk);
            Result<IReadOnlyList<string>, Failure> wsl =
                PackageCatalog.Default.ResolveWslTokens(seed.Value.WslTokens);
            Assert.True(wsl.IsOk);

            IReadOnlyList<string> winget = seed.Value.Komorebi
                ? [.. tools.Value.WingetInstallIds, "LGUG2Z.komorebi", "LGUG2Z.whkd"]
                : tools.Value.WingetInstallIds;

            Profile profile = new(
                new AccountProfile("winmint", "lab-only", false),
                new DmaProfile(true, new DmaSettleTarget("he-IL", 117, "Israel Standard Time", true)),
                DebloatMode.Online,
                debloat.Value.RemoveProvisionedAppx,
                winget,
                [],
                tools.Value.ScoopInstallIds,
                [],
                wsl.Value,
                [],
                debloat.Value.RemoveCapabilities,
                debloat.Value.DisableOptionalFeatures);

            string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(profile));
            // Outcome / preset ids must not appear as JSON string values (substring "Power" in AppX ids is fine).
            Assert.DoesNotContain("\"minimal\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"comfort\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"power\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"recommended\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"station\"", json, StringComparison.OrdinalIgnoreCase);
        }
    }
}
