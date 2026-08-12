using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Avalonia-free Included summary text — quiet labels from <see cref="ProductPosture"/>; What's included from effective AppX.</summary>
public static class IncludedSummary
{
    private const string QuietPrefix = "Also applied quietly: ";
    private const string QuietSeparator = " · ";

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
        PlanDiff.FriendlyRemoveNames(appxFamilyIds);

    public static string FormatWhatsIncluded(IEnumerable<string> appxFamilyIds) =>
        string.Join(QuietSeparator, FriendlyRemoveNames(appxFamilyIds));

    public static string FormatQuietSummary(int strippedAppCount) =>
        strippedAppCount > 0
            ? $"This build strips {strippedAppCount} apps."
            : "This build applies product defaults.";

}
