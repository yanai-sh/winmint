namespace WinMint.Orchestrator;

/// <summary>
/// Static in-repo catalog of legal provisioned AppX package family names for the keep-flag remove-list.
/// Plan validates ⊆ this set; ImageServicing (ticket 12) inventories the mount.
/// </summary>
public static class ProvisionedAppxCatalog
{
    /// <summary>Catalog ids are Profile remove-list entries (short package family names).</summary>
    public static IReadOnlySet<string> Ids { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        // KEEPFLAG sketch + common Win11 inbox provisioned families (legal remove-list only).
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.GamingApp",
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
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "MicrosoftCorporationII.QuickAssist",
    };

    public static bool Contains(string id) => Ids.Contains(id);
}
