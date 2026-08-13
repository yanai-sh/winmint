using System.Collections.Frozen;

namespace WinMint.Orchestrator;

/// <summary>
/// Always-on WinMint posture: AppX strip, winget/scoop shell-core constants, offline HKLM rows, DoH catalog.
/// Plan and Wizard consume effective lists from here — one locality for product locks.
/// </summary>
public static class ProductPosture
{
    public const string BraveWingetId = "Brave.Brave";
    public const string MinGitWingetId = "Git.MinGit";
    public const string PowerShellWingetId = "Microsoft.PowerShell";
    public const string WindowsTerminalWingetId = "Microsoft.WindowsTerminal";
    public const string CoreutilsWingetId = "Microsoft.Coreutils";
    public const string NilesoftShellWingetId = "Nilesoft.Shell";

    /// <summary>Install order: MinGit, pwsh, Terminal, Coreutils, Nilesoft Shell.</summary>
    public static IReadOnlyList<string> WingetIds { get; } =
    [
        MinGitWingetId,
        PowerShellWingetId,
        WindowsTerminalWingetId,
        CoreutilsWingetId,
        NilesoftShellWingetId,
    ];

    public static IReadOnlySet<string> WingetIdSet { get; } =
        WingetIds.ToFrozenSet(StringComparer.OrdinalIgnoreCase);

    /// <summary>Opinionated scoop CLI toolbox (Starship + Comfort-like tools + chezmoi).</summary>
    public static IReadOnlyList<string> ScoopIds { get; } =
    [
        "starship",
        "fzf",
        "fd",
        "ripgrep",
        "bat",
        "zoxide",
        "jq",
        "chezmoi",
    ];

    public static IReadOnlySet<string> ScoopIdSet { get; } =
        ScoopIds.ToFrozenSet(StringComparer.OrdinalIgnoreCase);

    public static IReadOnlyList<string> AppxIds { get; } =
    [
        "Microsoft.Copilot",
        "Microsoft.GamingApp",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxSpeechToTextOverlay",
    ];

    /// <summary>Quiet summary labels for always-on offline/FirstLogon posture (not AppX).</summary>
    public static IReadOnlyList<string> QuietLabels { get; } =
    [
        "Edge policies",
        "OneDrive",
        "device metadata",
        "WPBT",
        "long paths",
        "Widgets off",
        "consumer features off",
        "Store suggested apps off",
        "Developer Mode",
        "dark theme / DND",
        "Reserved Storage",
        "MinGit",
        "PowerShell 7",
        "Windows Terminal",
        "Nilesoft Shell",
        "Starship + scoop CLI",
        "shell skel stamp",
    ];

    public static IReadOnlyList<string> AlwaysOnDigestKeys =>
        ComposePolicies(includeBraveDebloat: false, includeDriverHygiene: false)
            .Select(static row => row.Digest)
            .Distinct(StringComparer.Ordinal)
            .ToArray();

    /// <summary>Profile appx first, then product-required; case-insensitive dedupe.</summary>
    public static IReadOnlyList<string> UnionAppx(IReadOnlyList<string> profileAppx) =>
        IdList.UnionOrdered(profileAppx, AppxIds);

    /// <summary>Constants first, then Profile winget ids; case-insensitive dedupe.</summary>
    public static IReadOnlyList<string> MergeWinget(IReadOnlyList<string> profileWinget) =>
        IdList.UnionOrdered(WingetIds, profileWinget);

    /// <summary>Constants first, then Profile scoop ids; case-insensitive dedupe.</summary>
    public static IReadOnlyList<string> MergeScoop(IReadOnlyList<string> profileScoop) =>
        IdList.UnionOrdered(ScoopIds, profileScoop);

    /// <summary>Drop product-constant winget ids from authored Profile text.</summary>
    public static string StripWingetFromAuthored(string? wingetMultiline) =>
        string.Join(
            Environment.NewLine,
            IdList.FromMultiline(wingetMultiline).Where(static id => !WingetIdSet.Contains(id)));

    /// <summary>Drop product-constant scoop ids from authored Profile text.</summary>
    public static string StripScoopFromAuthored(string? scoopMultiline) =>
        string.Join(
            Environment.NewLine,
            IdList.FromMultiline(scoopMultiline).Where(static id => !ScoopIdSet.Contains(id)));
    public static IReadOnlyList<OfflinePolicyRow> ComposePolicies(
        bool includeBraveDebloat,
        bool includeDriverHygiene = false)
    {
        List<OfflinePolicyRow> rows =
        [
            // Widgets/CloudContent before long Edge spray — creating Policies\Microsoft\Dsh
            // flakes Unauthorized after many offline reg writes on a DISM-mounted hive.
            .. WorkstationMachine,
            .. EdgeDebloat,
            .. OneDriveDisable,
            .. DeviceMetadata,
            .. WpbtDisable,
        ];
        if (includeBraveDebloat)
        {
            rows.AddRange(BraveDebloat);
        }

        if (includeDriverHygiene)
        {
            rows.AddRange(DriverHygiene);
        }

        return rows.ToArray();
    }

    public static bool TryNormalizeDohProvider(string? raw, out string? provider, out string? error)
    {
        provider = null;
        error = null;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return true;
        }

        string key = raw.Trim().ToLowerInvariant();
        if (DohProviders.ContainsKey(key))
        {
            provider = key;
            return true;
        }

        error =
            $"policies.dohProvider '{raw}' is unsupported (use cloudflare, google, or quad9).";
        return false;
    }

    public static DohProviderSpec? ResolveDoh(string providerId) =>
        DohProviders.TryGetValue(providerId, out DohProviderSpec? spec) ? spec : null;

    private static readonly Dictionary<string, DohProviderSpec> DohProviders =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["cloudflare"] = new(
                "1.1.1.1",
                "1.0.0.1",
                "https://cloudflare-dns.com/dns-query"),
            ["google"] = new(
                "8.8.8.8",
                "8.8.4.4",
                "https://dns.google/dns-query"),
            ["quad9"] = new(
                "9.9.9.9",
                "149.112.112.112",
                "https://dns.quad9.net/dns-query"),
        };

    private static readonly OfflinePolicyRow[] EdgeDebloat =
    [
        Soft("Policies\\Microsoft\\EdgeUpdate", "CreateDesktopShortcutDefault", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "PersonalizationReportingEnabled", "0", "edge"),
        SoftString("Policies\\Microsoft\\Edge\\ExtensionInstallBlocklist", "1", "ofefcgjbeghpigppfmkologfjadafddi", "edge"),
        Soft("Policies\\Microsoft\\Edge", "ShowRecommendationsEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "HideFirstRunExperience", "1", "edge"),
        SoftString("Policies\\Microsoft\\Edge", "NewTabPageLocation", "about:blank", "edge"),
        Soft("Policies\\Microsoft\\Edge", "UserFeedbackAllowed", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "ConfigureDoNotTrack", "1", "edge"),
        Soft("Policies\\Microsoft\\Edge", "AlternateErrorPagesEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "EdgeCollectionsEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "EdgeShoppingAssistantEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "MicrosoftEdgeInsiderPromotionEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "ShowMicrosoftRewards", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "WebWidgetAllowed", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "DiagnosticData", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "EdgeAssetDeliveryServiceEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "WalletDonationEnabled", "0", "edge"),
        Soft("Policies\\Microsoft\\Edge", "DefaultBrowserSettingsCampaignEnabled", "0", "edge"),
    ];

    /// <summary>
    /// Machine posture aligned with Microsoft Windows Developer Config (HKLM only).
    /// Skip RDP enable — widens attack surface on wipe-ready workstations.
    /// </summary>
    private static readonly OfflinePolicyRow[] WorkstationMachine =
    [
        // Widgets AllowNewsAndInterests: FirstLogon HKLM (offline Policies\Microsoft\Dsh create/set
        // flakes Unauthorized on this host's DISM-mounted SOFTWARE hive).
        Soft("Policies\\Microsoft\\Windows\\CloudContent", "DisableWindowsConsumerFeatures", "1", "cloudContent"),
        Soft("Policies\\Microsoft\\Windows\\CloudContent", "DisableSoftLanding", "1", "cloudContent"),
        Soft("Policies\\Microsoft\\WindowsStore", "AutoDownload", "2", "store"),
        Soft(@"Microsoft\Windows\CurrentVersion\AppModelUnlock", "AllowDevelopmentWithoutDevLicense", "1", "developer"),
        Soft(@"Microsoft\Windows\CurrentVersion\Sudo", "Enabled", "3", "sudo"),
        Sys("ControlSet001\\Control\\FileSystem", "LongPathsEnabled", "1", "filesystem"),
    ];

    private static readonly OfflinePolicyRow[] OneDriveDisable =
    [
        Soft("Policies\\Microsoft\\Windows\\OneDrive", "DisableFileSyncNGSC", "1", "onedrive"),
    ];

    private static readonly OfflinePolicyRow[] DeviceMetadata =
    [
        Soft("Policies\\Microsoft\\Windows\\Device Metadata", "PreventDeviceMetadataFromNetwork", "1", "device"),
    ];

    private static readonly OfflinePolicyRow[] WpbtDisable =
    [
        Sys("ControlSet001\\Control\\Session Manager", "DisableWpbtExecution", "1", "wpbt"),
    ];

    private static readonly OfflinePolicyRow[] DriverHygiene =
    [
        Soft(@"Microsoft\Windows\CurrentVersion\Device Installer", "DisableCoInstallers", "1", "deviceInstaller"),
    ];

    private static readonly OfflinePolicyRow[] BraveDebloat =
    [
        Soft("Policies\\BraveSoftware\\Brave", "BraveRewardsDisabled", "1", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveWalletDisabled", "1", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveVPNDisabled", "1", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveAIChatEnabled", "0", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveStatsPingEnabled", "0", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveNewsDisabled", "1", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveTalkDisabled", "1", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "TorDisabled", "1", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveP3AEnabled", "0", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "UrlKeyedAnonymizedDataCollectionEnabled", "0", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "SafeBrowsingExtendedReportingEnabled", "0", "brave"),
        Soft("Policies\\BraveSoftware\\Brave", "MetricsReportingEnabled", "0", "brave"),
    ];

    private static OfflinePolicyRow Soft(string subKey, string name, string data, string family) =>
        new("SOFTWARE", subKey, name, "REG_DWORD", data, family);

    private static OfflinePolicyRow SoftString(string subKey, string name, string data, string family) =>
        new("SOFTWARE", subKey, name, "REG_SZ", data, family);

    private static OfflinePolicyRow Sys(string subKey, string name, string data, string family) =>
        new("SYSTEM", subKey, name, "REG_DWORD", data, family);
}

/// <summary>One offline <c>reg add</c> row under SOFTWARE or SYSTEM hive. <see cref="Family"/> is declared, never inferred.</summary>
public sealed record OfflinePolicyRow(
    string Hive,
    string SubKey,
    string Name,
    string RegType,
    string Data,
    string Family)
{
    public string Digest => $"policy.{Family}.{Name}";
}

public sealed record DohProviderSpec(string Primary, string Secondary, string DohTemplate);
