namespace WinMint.Orchestrator;

/// <summary>
/// Static catalog of legal capability ids for <c>debloat.removeCapabilities</c> (ticket 20).
/// Inventory pin: 25H2 ARM64 English — thin acceptance pins in [DEBLOAT](../../docs/design/DEBLOAT.md).
/// </summary>
public static class CapabilityCatalog
{
    public static IReadOnlySet<string> Ids { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        // Thin acceptance pins + legal siblings from Installed inventory; recommended set lives in DebloatPresets (issue 56).
        "App.StepsRecorder~~~~0.0.1.0",
        "WMIC~~~~",
        "VBSCRIPT~~~~",
        "Browser.InternetExplorer~~~~0.0.11.0",
        "Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0",
        "MathRecognizer~~~~0.0.1.0",
        "Microsoft.Wallpapers.Extended~~~~0.0.1.0",
        "Print.Management.Console~~~~0.0.1.0",
        "Media.WindowsMediaPlayer~~~~0.0.12.0",
    };
}

/// <summary>
/// Static catalog of legal optional-feature names for <c>debloat.disableOptionalFeatures</c>.
/// </summary>
public static class OptionalFeatureCatalog
{
    public static IReadOnlySet<string> Ids { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "WorkFolders-Client",
        "WindowsMediaPlayer",
        "Printing-Foundation-InternetPrinting-Client",
        "Printing-XPSServices-Features",
        "TelnetClient",
        "TFTP",
        "SimpleTCP",
        "Microsoft-RemoteDesktopConnection",
    };
}
