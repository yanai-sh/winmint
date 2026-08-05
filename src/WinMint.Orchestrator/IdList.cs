namespace WinMint.Orchestrator;

/// <summary>Newline-separated id lists from host/UI text (trim lines, drop blanks, preserve order).</summary>
public static class IdList
{
    public static IReadOnlyList<string> FromMultiline(string? multiline) =>
        string.IsNullOrWhiteSpace(multiline)
            ? []
            : multiline.Split(['\r', '\n'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
}
