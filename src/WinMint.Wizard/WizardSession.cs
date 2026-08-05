using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Thin BuildPlan host glue — no Avalonia. Presets expand here; Profile JSON never carries preset names.</summary>
internal static class WizardSession
{
    public static WizardSessionResult ComposeAndPlan(WizardSessionInput input)
    {
        Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(input.Preset);
        if (!expanded.IsOk)
        {
            return WizardSessionResult.Fail($"{expanded.Error.Code}: {expanded.Error.Message}");
        }

        if (!int.TryParse(input.GeoIdText.Trim(), out int geoId))
        {
            return WizardSessionResult.Fail("dma.settle.geoId: must be an integer.");
        }

        // UI lists override empty; when non-empty they replace preset pins for that field (union would surprise).
        IReadOnlyList<string> caps = WizardProfileComposer.ParseIdList(input.RemoveCapabilitiesText);
        if (caps.Count == 0)
        {
            caps = expanded.Value.RemoveCapabilities;
        }

        IReadOnlyList<string> feats = WizardProfileComposer.ParseIdList(input.DisableOptionalFeaturesText);
        if (feats.Count == 0)
        {
            feats = expanded.Value.DisableOptionalFeatures;
        }

        byte[] utf8 = WizardProfileComposer.ToUtf8Json(
            input.Username.Trim(),
            input.Password,
            input.RequireWifiDuringOobe,
            input.DmaEnabled,
            input.Locale.Trim(),
            geoId,
            input.TimeZoneId.Trim(),
            input.LocationServicesEnabled,
            expanded.Value.RemoveProvisionedAppx,
            WizardProfileComposer.ParseIdList(input.WingetText),
            WizardProfileComposer.ParseIdList(input.WingetNeedsRebootText),
            WizardProfileComposer.ParseIdList(input.ScoopText),
            WizardProfileComposer.ParseIdList(input.ScoopNeedsRebootText),
            WizardProfileComposer.ParseIdList(input.WslText),
            WizardProfileComposer.ParseIdList(input.WslNeedsRebootText),
            caps,
            feats);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        if (!parsed.IsOk)
        {
            string issues = string.Join(
                Environment.NewLine,
                parsed.Error.Issues.Select(i => $"{i.Code}: {i.Message}" + (i.Path is null ? "" : $" ({i.Path})")));
            return WizardSessionResult.Fail(issues);
        }

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        if (!planned.IsOk)
        {
            return WizardSessionResult.Fail($"{planned.Error.Code}: {planned.Error.Message}");
        }

        string removeSummary = expanded.Value.RemoveProvisionedAppx.Count == 0
            ? "(none)"
            : string.Join(", ", expanded.Value.RemoveProvisionedAppx);
        string ok =
            $"Plan OK. Lane={planned.Value.Manifest.ImageQuality}; removeProvisionedAppx={removeSummary}; jobs={planned.Value.Jobs.Jobs.Count}.";
        return WizardSessionResult.Ok(ok, utf8, Encoding.UTF8.GetString(utf8));
    }
}

internal sealed record WizardSessionInput(
    string Preset,
    string Username,
    string Password,
    bool RequireWifiDuringOobe,
    bool DmaEnabled,
    string Locale,
    string GeoIdText,
    string TimeZoneId,
    bool LocationServicesEnabled,
    string WingetText = "",
    string WingetNeedsRebootText = "",
    string ScoopText = "",
    string ScoopNeedsRebootText = "",
    string WslText = "",
    string WslNeedsRebootText = "",
    string RemoveCapabilitiesText = "",
    string DisableOptionalFeaturesText = "");

internal sealed record WizardSessionResult(bool Succeeded, string Message, byte[]? ProfileUtf8, string? ProfileJson)
{
    public static WizardSessionResult Ok(string message, byte[] utf8, string json) =>
        new(true, message, utf8, json);

    public static WizardSessionResult Fail(string message) =>
        new(false, message, null, null);
}
