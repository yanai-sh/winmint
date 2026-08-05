using System.Globalization;
using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Thin BuildPlan host glue — no Avalonia. Presets expand here; Profile JSON never carries preset names.</summary>
internal static class WizardSession
{
    public static WizardSessionResult ComposeAndPlan(WizardSessionInput input)
    {
        Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(
            input.Preset,
            input.KeepGaming,
            input.KeepCopilot);
        if (!expanded.IsOk)
        {
            return WizardSessionResult.Fail($"{expanded.Error.Code}: {expanded.Error.Message}");
        }

        if (!int.TryParse(input.GeoIdText.Trim(), out int geoId))
        {
            return WizardSessionResult.Fail("dma.settle.geoId: must be an integer.");
        }

        if (!TryParseLane(input.ImageQualityText, out ImageQualityLane lane, out string? laneError))
        {
            return WizardSessionResult.Fail(laneError!);
        }

        IReadOnlyList<string> appx = IdList.FromMultiline(input.RemoveProvisionedAppxText);
        if (appx.Count == 0)
        {
            appx = expanded.Value.RemoveProvisionedAppx;
        }

        // UI lists override empty; when non-empty they replace preset pins for that field (union would surprise).
        IReadOnlyList<string> caps = IdList.FromMultiline(input.RemoveCapabilitiesText);
        if (caps.Count == 0)
        {
            caps = expanded.Value.RemoveCapabilities;
        }

        IReadOnlyList<string> feats = IdList.FromMultiline(input.DisableOptionalFeaturesText);
        if (feats.Count == 0)
        {
            feats = expanded.Value.DisableOptionalFeatures;
        }

        Profile profile = new(
            new AccountProfile(
                input.Username.Trim(),
                input.Password,
                input.RequireWifiDuringOobe),
            new DmaProfile(
                input.DmaEnabled,
                new DmaSettleTarget(
                    input.Locale.Trim(),
                    geoId,
                    input.TimeZoneId.Trim(),
                    input.LocationServicesEnabled)),
            appx,
            IdList.FromMultiline(input.WingetText),
            IdList.FromMultiline(input.WingetNeedsRebootText),
            IdList.FromMultiline(input.ScoopText),
            IdList.FromMultiline(input.ScoopNeedsRebootText),
            IdList.FromMultiline(input.WslText),
            IdList.FromMultiline(input.WslNeedsRebootText),
            caps,
            feats,
            new PoliciesProfile(KeepCopilot: input.KeepCopilot));

        RunOptions run = new()
        {
            ImageQuality = lane,
            SourceIsoPath = string.IsNullOrWhiteSpace(input.SourceIsoPath) ? null : input.SourceIsoPath.Trim(),
        };

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile, run);
        if (!planned.IsOk)
        {
            return WizardSessionResult.Fail($"{planned.Error.Code}: {planned.Error.Message}");
        }

        byte[] utf8 = BuildPlan.SerializeProfile(profile);
        string removeSummary = appx.Count == 0
            ? "(none)"
            : string.Join(", ", appx);
        string ok =
            $"Plan OK. Lane={planned.Value.Manifest.ImageQuality}; removeProvisionedAppx={removeSummary}; jobs={planned.Value.Jobs.Jobs.Count}.";
        return WizardSessionResult.Ok(ok, utf8, Encoding.UTF8.GetString(utf8));
    }

    /// <summary>Honest Phase A handoff — no process spawn. Work dir is a conventional placeholder.</summary>
    public static string FormatBuildRecipe(
        string profilePath,
        string sourceIsoPath,
        string imageQualityText,
        int? wimIndex)
    {
        string profile = QuoteArg(profilePath);
        string iso = QuoteArg(sourceIsoPath);
        string lane = string.IsNullOrWhiteSpace(imageQualityText) ? "Test" : imageQualityText.Trim();
        StringBuilder sb = new();
        sb.Append(CultureInfo.InvariantCulture, $"winmint build {profile} --iso {iso} --work \"%ProgramData%\\WinMint\\work\" --image-quality {lane}");
        // Cli defaults WIM index to Pro when omitted — always emit Home (and any non-Pro) so the recipe matches Wizard intent.
        if (wimIndex is int index)
        {
            if (index != ImageServicing.DefaultProWimIndex)
            {
                sb.Append(CultureInfo.InvariantCulture, $" --wim-index {index}");
            }
        }

        return sb.ToString();
    }

    public static bool TryParseLane(string? raw, out ImageQualityLane lane, out string? error)
    {
        lane = ImageQualityLane.Test;
        error = null;
        if (string.IsNullOrWhiteSpace(raw) ||
            string.Equals(raw.Trim(), "Test", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (string.Equals(raw.Trim(), "Release", StringComparison.OrdinalIgnoreCase))
        {
            lane = ImageQualityLane.Release;
            return true;
        }

        error = "run.imageQuality: must be Test or Release.";
        return false;
    }

    /// <summary>Advanced multiline wins when non-empty; else selected chip ids; else empty (preset fills).</summary>
    public static string MergeChipAndAdvanced(IEnumerable<string> selectedChipIds, string? advancedMultiline)
    {
        IReadOnlyList<string> advanced = IdList.FromMultiline(advancedMultiline);
        if (advanced.Count > 0)
        {
            return string.Join(Environment.NewLine, advanced);
        }

        List<string> chips = selectedChipIds
            .Where(static id => !string.IsNullOrWhiteSpace(id))
            .Select(static id => id.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        return string.Join(Environment.NewLine, chips);
    }

    private static string QuoteArg(string path)
    {
        string trimmed = path.Trim();
        if (trimmed.Contains('"', StringComparison.Ordinal))
        {
            trimmed = trimmed.Replace("\"", "\\\"", StringComparison.Ordinal);
        }

        return $"\"{trimmed}\"";
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
    bool KeepGaming = false,
    bool KeepCopilot = false,
    string WingetText = "",
    string WingetNeedsRebootText = "",
    string ScoopText = "",
    string ScoopNeedsRebootText = "",
    string WslText = "",
    string WslNeedsRebootText = "",
    string RemoveCapabilitiesText = "",
    string DisableOptionalFeaturesText = "",
    string RemoveProvisionedAppxText = "",
    string SourceIsoPath = "",
    string ImageQualityText = "Test",
    int? WimIndex = null);

internal sealed record WizardSessionResult(bool Succeeded, string Message, byte[]? ProfileUtf8, string? ProfileJson)
{
    public static WizardSessionResult Ok(string message, byte[] utf8, string json) =>
        new(true, message, utf8, json);

    public static WizardSessionResult Fail(string message) =>
        new(false, message, null, null);
}
