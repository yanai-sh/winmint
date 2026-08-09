namespace WinMint.Orchestrator;

/// <summary>Product-required AppX removals, independent of Profile keep flags.</summary>
public static class ProductRequiredStrip
{
    public static IReadOnlyList<string> AppxIds { get; } =
    [
        "Microsoft.Copilot",
        "Microsoft.GamingApp",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
    ];

    public static IReadOnlyList<string> UnionAppx(IReadOnlyList<string> profileAppx)
    {
        List<string> merged = [];
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        foreach (string id in profileAppx.Concat(AppxIds))
        {
            if (seen.Add(id))
            {
                merged.Add(id);
            }
        }

        return merged;
    }
}
