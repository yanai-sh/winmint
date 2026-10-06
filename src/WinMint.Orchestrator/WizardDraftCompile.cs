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

        Result<DmaProfile, Failure> dma = ProfileDraft.TryParseDma(
            request.DmaEnabled,
            request.Locale,
            request.GeoId,
            request.TimeZoneId,
            request.LocationServices);
        if (!dma.IsOk)
        {
            return Result.Fail<WizardDraft, Failure>(dma.Error);
        }

        AccountProfile account = new(
            request.Username.Trim(),
            request.Password,
            request.RequireWifi);

        Result<Profile, Failure> profile = ProfileDraft.TryBuild(
            request.StationOutcome,
            account,
            dma.Value,
            request.Packages,
            request.AdvancedWinget,
            request.AdvancedScoop,
            request.AdvancedWsl);
        if (!profile.IsOk)
        {
            return Result.Fail<WizardDraft, Failure>(profile.Error);
        }

        HostComposeOptions options = new(
            request.SourceIsoPath ?? "",
            ImageQualityLane.Release,
            WimIndex: request.WimIndex,
            ProfileName: ShippingProfileName,
            PackageStrict: PackageStrictOverride.FromLane,
            AuthoredSelectionLabels: [.. request.SelectionLabels]);

        return Result.Ok<WizardDraft, Failure>(new WizardDraft(profile.Value, options));
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
