namespace WinMint.Provisioning;

/// <summary>
/// Resolve XDG basedir roots and Komorebi config home from the process environment,
/// with Freedesktop / product fallbacks under the user profile.
/// </summary>
internal static class XdgPaths
{
    public const string KomorebiConfigHomeEnvName = "KOMOREBI_CONFIG_HOME";

    public static string ConfigHome =>
        Resolve("XDG_CONFIG_HOME", static profile => Path.Combine(profile, ".config"));

    public static string DataHome =>
        Resolve("XDG_DATA_HOME", static profile => Path.Combine(profile, ".local", "share"));

    public static string StateHome =>
        Resolve("XDG_STATE_HOME", static profile => Path.Combine(profile, ".local", "state"));

    public static string CacheHome =>
        Resolve("XDG_CACHE_HOME", static profile => Path.Combine(profile, ".cache"));

    /// <summary>
    /// KOMOREBI_CONFIG_HOME if somehow set (manual override / tests); otherwise <see cref="ConfigHome"/>\komorebi.
    /// WinMint never stamps this env — pass explicit <c>--config</c> to komorebic.
    /// </summary>
    public static string KomorebiConfigHome
    {
        get
        {
            string? fromEnv = ReadExpanded(KomorebiConfigHomeEnvName);
            return !string.IsNullOrWhiteSpace(fromEnv)
                ? fromEnv
                : Path.Combine(ConfigHome, "komorebi");
        }
    }

    private static string Resolve(string variable, Func<string, string> fallbackUnderProfile)
    {
        string? fromEnv = ReadExpanded(variable);
        if (!string.IsNullOrWhiteSpace(fromEnv))
        {
            return fromEnv;
        }

        string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return fallbackUnderProfile(profile);
    }

    private static string? ReadExpanded(string variable)
    {
        string? raw = Environment.GetEnvironmentVariable(variable);
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        string expanded = Environment.ExpandEnvironmentVariables(raw.Trim());
        return string.IsNullOrWhiteSpace(expanded) ? null : expanded;
    }
}
