namespace WinMint.Orchestrator;

/// <summary>
/// Host-side named presets that expand to debloat remove-lists.
/// Preset names never appear in Profile JSON ([KEEPFLAG] / ADR-005 / issue 56).
/// </summary>
public static class KeepFlagPresets
{
    public const string Empty = "empty";
    public const string Acceptance = "acceptance";
    public const string Recommended = "recommended";

    /// <summary>Pinned acceptance AppX remove-list (samples/acceptance.profile.json / ticket 14).</summary>
    private static readonly string[] AcceptanceAppx =
    [
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
    ];

    /// <summary>Thin acceptance capability pins (ticket 19/20 / ticket 25).</summary>
    private static readonly string[] AcceptanceCapabilities =
    [
        "App.StepsRecorder~~~~0.0.1.0",
        "WMIC~~~~",
    ];

    /// <summary>Thin acceptance optional-feature pins (ticket 19/20 / ticket 25).</summary>
    private static readonly string[] AcceptanceFeatures =
    [
        "WorkFolders-Client",
    ];

    /// <summary>
    /// Product zero-config AppX strip (issue 56). Catalog-bound; catalog growth does not auto-expand this list.
    /// Gaming families are included unless keepGaming subtracts them.
    /// </summary>
    private static readonly string[] RecommendedAppxCore =
    [
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.People",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.Todos",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "MicrosoftCorporationII.QuickAssist",
    ];

    private static readonly string[] RecommendedAppxGaming =
    [
        "Microsoft.GamingApp",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
    ];

    private static readonly string[] RecommendedCapabilities =
    [
        "App.StepsRecorder~~~~0.0.1.0",
        "WMIC~~~~",
        "VBSCRIPT~~~~",
        "Browser.InternetExplorer~~~~0.0.11.0",
        "Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0",
        "Microsoft.Wallpapers.Extended~~~~0.0.1.0",
        "Media.WindowsMediaPlayer~~~~0.0.12.0",
    ];

    private static readonly string[] RecommendedFeatures =
    [
        "WorkFolders-Client",
        "WindowsMediaPlayer",
        "TelnetClient",
        "TFTP",
        "SimpleTCP",
    ];

    public static Result<KeepFlagExpansion, PlanFailure> TryExpand(
        string name,
        bool keepGaming = false,
        bool keepCopilot = false)
    {
        _ = keepCopilot; // ponytail: Slice 2 Copilot/Recall catalog — KeepCopilot is UI stub until then

        if (string.IsNullOrWhiteSpace(name))
        {
            return Result.Fail<KeepFlagExpansion, PlanFailure>(
                new PlanFailure("keepflag.preset.unknown", "Preset name is required."));
        }

        string key = name.Trim();
        if (string.Equals(key, Empty, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<KeepFlagExpansion, PlanFailure>(KeepFlagExpansion.Empty);
        }

        if (string.Equals(key, Acceptance, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<KeepFlagExpansion, PlanFailure>(
                new KeepFlagExpansion(AcceptanceAppx, AcceptanceCapabilities, AcceptanceFeatures));
        }

        if (string.Equals(key, Recommended, StringComparison.OrdinalIgnoreCase))
        {
            string[] appx = keepGaming
                ? RecommendedAppxCore
                : [.. RecommendedAppxCore, .. RecommendedAppxGaming];
            return Result.Ok<KeepFlagExpansion, PlanFailure>(
                new KeepFlagExpansion(appx, RecommendedCapabilities, RecommendedFeatures));
        }

        return Result.Fail<KeepFlagExpansion, PlanFailure>(
            new PlanFailure("keepflag.preset.unknown", $"Unknown keep-flag preset '{key}'."));
    }
}

/// <summary>Host-expanded debloat lists (never serialized as a preset name).</summary>
public sealed record KeepFlagExpansion(
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures)
{
    public static KeepFlagExpansion Empty { get; } = new([], [], []);
}
