using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>
/// Wizard UI snapshot → Profile + shipping HostComposeOptions.
/// Front ends collect fields; this module owns draft compile and shipping pins (ADR-016).
/// </summary>
public static class WizardDraftCompile
{
    public const string ShippingProfileName = "winmint.profile.json";

    /// <summary>
    /// Build a shipping draft: remove-lists from Station seed(outcome); packages from refined UI selection.
    /// </summary>
    public static Result<WizardDraft, Failure> TryCompile(WizardDraftRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentNullException.ThrowIfNull(request.Packages);

        Result<StationSeed, Failure> seed = StationOutcomes.TrySeed(request.StationOutcome);
        if (!seed.IsOk)
        {
            return Result.Fail<WizardDraft, Failure>(seed.Error);
        }

        if (!int.TryParse(request.GeoId.Trim(), out int geoId))
        {
            return Result.Fail<WizardDraft, Failure>(
                new Failure("dma.settle.geoId", "must be an integer."));
        }

        PackageSelection packages = request.Packages;
        Profile profile = new(
            new AccountProfile(
                request.Username.Trim(),
                request.Password,
                request.RequireWifi),
            new DmaProfile(
                request.DmaEnabled,
                new DmaSettleTarget(
                    request.Locale.Trim(),
                    geoId,
                    request.TimeZoneId.Trim(),
                    request.LocationServices)),
            DebloatMode.Online,
            seed.Value.RemoveProvisionedAppx,
            IdList.FromMultiline(
                MergeChipAndAdvanced(packages.WingetInstallIds, request.AdvancedWinget)),
            [],
            IdList.FromMultiline(
                MergeChipAndAdvanced(packages.ScoopInstallIds, request.AdvancedScoop)),
            [],
            IdList.FromMultiline(
                MergeChipAndAdvanced(packages.WslProfileTokens, request.AdvancedWsl)),
            [],
            seed.Value.RemoveCapabilities,
            seed.Value.DisableOptionalFeatures);

        HostComposeOptions options = new(
            request.SourceIsoPath ?? "",
            ImageQualityLane.Release,
            WimIndex: request.WimIndex,
            ProfileName: ShippingProfileName,
            PackageStrict: PackageStrictOverride.FromLane,
            AuthoredSelectionLabels: [.. request.SelectionLabels]);

        return Result.Ok<WizardDraft, Failure>(new WizardDraft(profile, options));
    }

    private static string MergeChipAndAdvanced(
        IEnumerable<string> selectedChipIds,
        string? advancedMultiline)
    {
        IReadOnlyList<string> advanced = IdList.FromMultiline(advancedMultiline);
        return string.Join(
            Environment.NewLine,
            selectedChipIds
                .Concat(advanced)
                .Where(static id => !string.IsNullOrWhiteSpace(id))
                .Select(static id => id.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase));
    }
}

/// <summary>Wizard-collected fields for <see cref="WizardDraftCompile"/>.</summary>
public sealed record WizardDraftRequest(
    string Username,
    string? Password,
    bool RequireWifi,
    bool DmaEnabled,
    string Locale,
    string GeoId,
    string TimeZoneId,
    bool LocationServices,
    string StationOutcome,
    PackageSelection Packages,
    string? AdvancedWinget,
    string? AdvancedScoop,
    string? AdvancedWsl,
    string? SourceIsoPath,
    int WimIndex,
    IReadOnlyList<string> SelectionLabels);

/// <summary>Compiled Wizard draft ready for HostCompile.</summary>
public sealed record WizardDraft(Profile Profile, HostComposeOptions Options);
