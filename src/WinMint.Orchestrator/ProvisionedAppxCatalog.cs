namespace WinMint.Orchestrator;

/// <summary>
/// Static in-repo catalog of legal provisioned AppX package family names for the Debloat remove-list.
/// Plan validates ⊆ this set; ImageServicing (ticket 12) inventories the mount.
/// </summary>
public static class ProvisionedAppxCatalog
{
    /// <summary>Catalog ids are Profile remove-list entries (short package family names).</summary>
    public static IReadOnlySet<string> Ids { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        // DEBLOAT sketch + common Win11 inbox provisioned families (legal remove-list only).
        "Clipchamp.Clipchamp",
        "Microsoft.BingNews",
        "Microsoft.BingSearch",
        "Microsoft.BingWeather",
        "Microsoft.Copilot",
        "Microsoft.GamingApp",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.OutlookForWindows",
        "Microsoft.People",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.StartExperiencesApp",
        "Microsoft.Todos",
        "Microsoft.Windows.DevHome",
        "Microsoft.WindowsAlarms",
        "Microsoft.Windows.CrossDevice",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "MicrosoftCorporationII.QuickAssist",
        "MicrosoftTeams",
        "MSTeams",
    };
}
