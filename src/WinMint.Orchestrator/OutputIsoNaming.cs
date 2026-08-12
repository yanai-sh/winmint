using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace WinMint.Orchestrator;

/// <summary>Default Output ISO leaf when <c>OutputIsoPath</c> / <c>--out-iso</c> is unset. Owned by ImageServicing.</summary>
internal static partial class OutputIsoNaming
{
    /// <summary>Profile path → sanitized stem (<c>sl7.profile.json</c> → <c>sl7</c>).</summary>
    public static string ProfileStem(string? profilePath)
    {
        if (string.IsNullOrWhiteSpace(profilePath))
        {
            return "profile";
        }

        string name = Path.GetFileName(profilePath.Trim());
        if (name.EndsWith(".profile.json", StringComparison.OrdinalIgnoreCase))
        {
            name = name[..^".profile.json".Length];
        }
        else if (name.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
        {
            name = name[..^".json".Length];
        }
        else
        {
            name = Path.GetFileNameWithoutExtension(name);
        }

        string sanitized = Sanitize(name);
        return string.IsNullOrEmpty(sanitized) ? "profile" : sanitized;
    }

    public static string DefaultFileName(
        string? profilePath,
        ImageQualityLane lane,
        DateTimeOffset timestamp) =>
        string.Create(
            CultureInfo.InvariantCulture,
            $"winmint_{ProfileStem(profilePath)}_{lane}_{timestamp.ToLocalTime():yyyyMMdd-HHmmss}.iso");

    public static string DefaultPath(
        string workDirectory,
        string? profilePath,
        ImageQualityLane lane,
        DateTimeOffset timestamp) =>
        Path.Combine(
            workDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            DefaultFileName(profilePath, lane, timestamp));

    public static string DefaultPath(
        string workDirectory,
        string? profilePath,
        ImageQualityLane lane,
        TimeProvider? time = null) =>
        DefaultPath(workDirectory, profilePath, lane, (time ?? TimeProvider.System).GetLocalNow());

    private static string Sanitize(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        StringBuilder sb = new(value.Length);
        foreach (char c in value.Trim())
        {
            if (c is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z') or (>= '0' and <= '9') or '.' or '_' or '-')
            {
                sb.Append(c);
            }
            else if (char.IsWhiteSpace(c) || c is '/' or '\\' or ':' or '"' or '<' or '>' or '|' or '?' or '*')
            {
                sb.Append('_');
            }
        }

        string s = CollapseUnderscores().Replace(sb.ToString(), "_").Trim('_');
        return s;
    }

    [GeneratedRegex("_{2,}")]
    private static partial Regex CollapseUnderscores();
}
