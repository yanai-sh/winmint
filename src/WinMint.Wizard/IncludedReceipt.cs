using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Avalonia-free Included receipt text — quiet labels from <see cref="ProductPosture"/>; What's included from effective AppX.</summary>
public static class IncludedReceipt
{
    private const string QuietPrefix = "Also applied quietly: ";
    private const string QuietSeparator = " · ";

    private static readonly Dictionary<string, string> RecommendedAppxLabels =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["Microsoft.BingNews"] = "Bing News",
            ["Microsoft.BingWeather"] = "Bing Weather",
            ["Microsoft.GetHelp"] = "Get Help",
            ["Microsoft.Getstarted"] = "Get Started",
            ["Microsoft.MicrosoftOfficeHub"] = "Office Hub",
            ["Microsoft.MicrosoftSolitaireCollection"] = "Solitaire",
            ["Microsoft.People"] = "People",
            ["Microsoft.PowerAutomateDesktop"] = "Power Automate",
            ["Microsoft.Todos"] = "To Do",
            ["Microsoft.WindowsAlarms"] = "Alarms",
            ["Microsoft.WindowsFeedbackHub"] = "Feedback Hub",
            ["Microsoft.WindowsMaps"] = "Maps",
            ["Microsoft.YourPhone"] = "Phone Link",
            ["Microsoft.ZuneMusic"] = "Zune Music",
            ["Microsoft.ZuneVideo"] = "Movies & TV",
            ["MicrosoftCorporationII.QuickAssist"] = "Quick Assist",
            ["Microsoft.GamingApp"] = "Xbox app",
            ["Microsoft.Xbox.TCUI"] = "Xbox TCUI",
            ["Microsoft.XboxGamingOverlay"] = "Game Bar",
            ["Microsoft.XboxSpeechToTextOverlay"] = "Xbox speech overlay",
            ["Microsoft.Copilot"] = "Copilot",
        };

    public static string FormatQuietBlock(bool braveSelected)
    {
        List<string> parts = [.. ProductPosture.QuietLabels];
        if (braveSelected)
        {
            parts.Add("Brave policies");
        }

        return QuietPrefix + string.Join(QuietSeparator, parts);
    }

    public static string FormatPickStrip(IEnumerable<string>? pickLabels)
    {
        if (pickLabels is null)
        {
            return string.Empty;
        }

        string[] labels = pickLabels
            .Where(static label => !string.IsNullOrWhiteSpace(label))
            .Select(static label => label.Trim())
            .ToArray();

        return labels.Length == 0 ? string.Empty : string.Join(QuietSeparator, labels);
    }

    public static IReadOnlyList<string> FriendlyRemoveNames(IEnumerable<string> appxFamilyIds) =>
        appxFamilyIds.Select(FriendlyRemoveName).ToArray();

    public static string FormatWhatsIncluded(IEnumerable<string> appxFamilyIds) =>
        string.Join(QuietSeparator, FriendlyRemoveNames(appxFamilyIds));

    public static string FormatQuietSummary(int strippedAppCount) =>
        strippedAppCount > 0
            ? $"This build strips {strippedAppCount} apps."
            : "This build applies product defaults.";

    private static string FriendlyRemoveName(string appxFamilyId)
    {
        if (RecommendedAppxLabels.TryGetValue(appxFamilyId, out string? label))
        {
            return label;
        }

        int dot = appxFamilyId.LastIndexOf('.');
        return dot >= 0 && dot < appxFamilyId.Length - 1
            ? appxFamilyId[(dot + 1)..]
            : appxFamilyId;
    }
}
