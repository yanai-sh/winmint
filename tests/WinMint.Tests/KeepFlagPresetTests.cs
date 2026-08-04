using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 15 — host-side keep-flag presets expand to remove-list (not in Profile JSON).</summary>
public class KeepFlagPresetTests
{
    [Fact]
    public void Expand_acceptance_returns_pinned_acceptance_ids()
    {
        Result<IReadOnlyList<string>, PresetFailure> result = KeepFlagPresets.TryExpand("acceptance");

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Equal(
            ["Microsoft.BingNews", "Microsoft.BingWeather"],
            result.Value);
    }

    [Fact]
    public void Expand_empty_returns_no_ids()
    {
        Result<IReadOnlyList<string>, PresetFailure> result = KeepFlagPresets.TryExpand("empty");

        Assert.True(result.IsOk);
        Assert.Empty(result.Value);
    }

    [Fact]
    public void Expand_unknown_preset_fails()
    {
        Result<IReadOnlyList<string>, PresetFailure> result = KeepFlagPresets.TryExpand("not-a-preset");

        Assert.False(result.IsOk);
        Assert.Equal("keepflag.preset.unknown", result.Error.Code);
        Assert.Contains("not-a-preset", result.Error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Compose_acceptance_preset_parses_and_plans()
    {
        Result<IReadOnlyList<string>, PresetFailure> expanded = KeepFlagPresets.TryExpand(KeepFlagPresets.Acceptance);
        Assert.True(expanded.IsOk);

        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            username: "winmint",
            password: "lab-only",
            requireWifiDuringOobe: false,
            dmaEnabled: true,
            locale: "en-GB",
            geoId: 242,
            timeZoneId: "GMT Standard Time",
            locationServicesEnabled: true,
            removeProvisionedAppx: expanded.Value);

        // Preset name must not appear in Profile JSON (host expands only).
        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("acceptance", json, StringComparison.OrdinalIgnoreCase);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Issues.Select(i => i.Code)));
        Assert.Equal(["Microsoft.BingNews", "Microsoft.BingWeather"], parsed.Value.RemoveProvisionedAppx);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
    }

    [Fact]
    public void Compose_empty_preset_plans_without_remove_stage()
    {
        Result<IReadOnlyList<string>, PresetFailure> expanded = KeepFlagPresets.TryExpand(KeepFlagPresets.Empty);
        Assert.True(expanded.IsOk);

        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            username: "winmint",
            password: "lab-only",
            requireWifiDuringOobe: false,
            dmaEnabled: true,
            locale: "en-GB",
            geoId: 242,
            timeZoneId: "GMT Standard Time",
            locationServicesEnabled: true,
            removeProvisionedAppx: expanded.Value);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);
        Assert.Empty(parsed.Value.RemoveProvisionedAppx);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk);
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
    }
}
