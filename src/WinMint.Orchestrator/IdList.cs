namespace WinMint.Orchestrator;

/// <summary>Newline-separated id lists from host/UI text (trim lines, drop blanks, preserve order).</summary>
public static class IdList
{
    public static IReadOnlyList<string> FromMultiline(string? multiline) =>
        string.IsNullOrWhiteSpace(multiline)
            ? []
            : multiline.Split(['\r', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    /// <summary>Case-insensitive ordered union; blanks skipped; first occurrence wins.</summary>
    public static IReadOnlyList<string> UnionOrdered(IEnumerable<string> first, IEnumerable<string> second)
    {
        List<string> merged = [];
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        foreach (string id in first.Concat(second))
        {
            if (string.IsNullOrWhiteSpace(id))
            {
                continue;
            }

            string trimmed = id.Trim();
            if (seen.Add(trimmed))
            {
                merged.Add(trimmed);
            }
        }

        return [.. merged];
    }
}
