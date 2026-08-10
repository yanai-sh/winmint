namespace WinMint.Orchestrator;

/// <summary>
/// Host-side named presets that expand to debloat remove-lists.
/// Preset names never appear in Profile JSON ([DEBLOAT] / ADR-005 / issue 56).
/// Copilot/gaming AppX are product-required via <see cref="ProductPosture"/> — not preset overlays.
/// </summary>
public static class DebloatPresets
{
    public const string Empty = "empty";
    public const string Acceptance = "acceptance";
    public const string Recommended = "recommended";

    private static readonly string[] AcceptanceAppx =
    [
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
    ];

    private static readonly string[] AcceptanceCapabilities =
    [
        "App.StepsRecorder~~~~0.0.1.0",
        "WMIC~~~~",
    ];

    private static readonly string[] AcceptanceFeatures =
    [
        "WorkFolders-Client",
    ];

    /// <summary>
    /// Product zero-config AppX strip (issue 56). Catalog-bound; catalog growth does not auto-expand this list.
    /// </summary>
    private static readonly string[] RecommendedAppx =
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

    public static Result<DebloatExpansion, Failure> TryExpand(string name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return Result.Fail<DebloatExpansion, Failure>(
                new Failure("debloat.preset.unknown", "Preset name is required."));
        }

        string key = name.Trim();
        if (string.Equals(key, Empty, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<DebloatExpansion, Failure>(DebloatExpansion.Empty);
        }

        if (string.Equals(key, Acceptance, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<DebloatExpansion, Failure>(
                new DebloatExpansion(AcceptanceAppx, AcceptanceCapabilities, AcceptanceFeatures));
        }

        if (string.Equals(key, Recommended, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Ok<DebloatExpansion, Failure>(
                new DebloatExpansion(RecommendedAppx, RecommendedCapabilities, RecommendedFeatures));
        }

        return Result.Fail<DebloatExpansion, Failure>(
            new Failure("debloat.preset.unknown", $"Unknown debloat preset '{key}'."));
    }
}

/// <summary>Host-expanded debloat lists (never serialized as a preset name).</summary>
public sealed record DebloatExpansion(
    IReadOnlyList<string> RemoveProvisionedAppx,
    IReadOnlyList<string> RemoveCapabilities,
    IReadOnlyList<string> DisableOptionalFeatures)
{
    public static DebloatExpansion Empty { get; } = new([], [], []);
}
