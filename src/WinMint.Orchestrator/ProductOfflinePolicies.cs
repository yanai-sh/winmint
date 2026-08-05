namespace WinMint.Orchestrator;

/// <summary>
/// Product-constant + conditional offline HKLM policy rows (winutil EdgeDebloat / BraveDebloat / essentials).
/// Plan owns branching; StampOfflinePolicies kernel is param-only ([ADR-009]).
/// </summary>
public static class ProductOfflinePolicies
{
    public const string BraveWingetId = "Brave.Brave";

    /// <summary>Copilot AppX families host may union into remove-list when <c>keepCopilot</c> is false.</summary>
    public static IReadOnlyList<string> CopilotAppxIds { get; } =
    [
        "Microsoft.Copilot",
    ];

    public static IReadOnlyList<OfflinePolicyRow> Compose(
        bool keepCopilot,
        bool includeBraveDebloat,
        bool includeDriverHygiene = false)
    {
        List<OfflinePolicyRow> rows = [.. EdgeDebloat, .. OneDriveDisable, .. DeviceMetadata, .. WpbtDisable];
        if (!keepCopilot)
        {
            rows.AddRange(CopilotKill);
        }

        if (includeBraveDebloat)
        {
            rows.AddRange(BraveDebloat);
        }

        if (includeDriverHygiene)
        {
            rows.AddRange(DriverHygiene);
        }

        return rows;
    }

    public static string EncodeSpecs(IReadOnlyList<OfflinePolicyRow> rows) =>
        string.Join(';', rows.Select(r => $"{r.Hive}|{r.SubKey}|{r.Name}|{r.RegType}|{r.Data}"));

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

    // winutil WPFTweaksEdgeDebloat — 17 HKLM Edge / EdgeUpdate policies (no HubsSidebar / Copilot).
    private static readonly OfflinePolicyRow[] EdgeDebloat =
    [
        Soft("Policies\\Microsoft\\EdgeUpdate", "CreateDesktopShortcutDefault", "0"),
        Soft("Policies\\Microsoft\\Edge", "PersonalizationReportingEnabled", "0"),
        SoftString("Policies\\Microsoft\\Edge\\ExtensionInstallBlocklist", "1", "ofefcgjbeghpigppfmkologfjadafddi"),
        Soft("Policies\\Microsoft\\Edge", "ShowRecommendationsEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "HideFirstRunExperience", "1"),
        Soft("Policies\\Microsoft\\Edge", "UserFeedbackAllowed", "0"),
        Soft("Policies\\Microsoft\\Edge", "ConfigureDoNotTrack", "1"),
        Soft("Policies\\Microsoft\\Edge", "AlternateErrorPagesEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "EdgeCollectionsEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "EdgeShoppingAssistantEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "MicrosoftEdgeInsiderPromotionEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "ShowMicrosoftRewards", "0"),
        Soft("Policies\\Microsoft\\Edge", "WebWidgetAllowed", "0"),
        Soft("Policies\\Microsoft\\Edge", "DiagnosticData", "0"),
        Soft("Policies\\Microsoft\\Edge", "EdgeAssetDeliveryServiceEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "WalletDonationEnabled", "0"),
        Soft("Policies\\Microsoft\\Edge", "DefaultBrowserSettingsCampaignEnabled", "0"),
    ];

    private static readonly OfflinePolicyRow[] OneDriveDisable =
    [
        Soft("Policies\\Microsoft\\Windows\\OneDrive", "DisableFileSyncNGSC", "1"),
    ];

    private static readonly OfflinePolicyRow[] DeviceMetadata =
    [
        Soft("Policies\\Microsoft\\Windows\\Device Metadata", "PreventDeviceMetadataFromNetwork", "1"),
    ];

    // Offline SYSTEM hive: ControlSet001 (CurrentControlSet is online-only).
    private static readonly OfflinePolicyRow[] WpbtDisable =
    [
        new(
            "SYSTEM",
            "ControlSet001\\Control\\Session Manager",
            "DisableWpbtExecution",
            "REG_DWORD",
            "1",
            "policy.wpbt.DisableWpbtExecution"),
    ];

    private static readonly OfflinePolicyRow[] CopilotKill =
    [
        Soft("Policies\\Microsoft\\Edge", "HubsSidebarEnabled", "0"),
        Soft("Policies\\Microsoft\\Windows\\WindowsCopilot", "TurnOffWindowsCopilot", "1"),
    ];

    // v1 driver hygiene — stamped when Surface Catalog injection is selected (issue 63).
    private static readonly OfflinePolicyRow[] DriverHygiene =
    [
        new(
            "SOFTWARE",
            @"Microsoft\Windows\CurrentVersion\Device Installer",
            "DisableCoInstallers",
            "REG_DWORD",
            "1",
            "policy.deviceInstaller.DisableCoInstallers"),
    ];

    // winutil WPFTweaksBraveDebloat — 12 BraveSoftware policies.
    private static readonly OfflinePolicyRow[] BraveDebloat =
    [
        Soft("Policies\\BraveSoftware\\Brave", "BraveRewardsDisabled", "1"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveWalletDisabled", "1"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveVPNDisabled", "1"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveAIChatEnabled", "0"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveStatsPingEnabled", "0"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveNewsDisabled", "1"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveTalkDisabled", "1"),
        Soft("Policies\\BraveSoftware\\Brave", "TorDisabled", "1"),
        Soft("Policies\\BraveSoftware\\Brave", "BraveP3AEnabled", "0"),
        Soft("Policies\\BraveSoftware\\Brave", "UrlKeyedAnonymizedDataCollectionEnabled", "0"),
        Soft("Policies\\BraveSoftware\\Brave", "SafeBrowsingExtendedReportingEnabled", "0"),
        Soft("Policies\\BraveSoftware\\Brave", "MetricsReportingEnabled", "0"),
    ];

    private static OfflinePolicyRow Soft(string subKey, string name, string data) =>
        new("SOFTWARE", subKey, name, "REG_DWORD", data, $"policy.{DigestFamily(subKey)}.{name}");

    private static OfflinePolicyRow SoftString(string subKey, string name, string data) =>
        new("SOFTWARE", subKey, name, "REG_SZ", data, $"policy.{DigestFamily(subKey)}.{name}");

    private static string DigestFamily(string subKey)
    {
        if (subKey.Contains("BraveSoftware", StringComparison.OrdinalIgnoreCase))
        {
            return "brave";
        }

        if (subKey.Contains("OneDrive", StringComparison.OrdinalIgnoreCase))
        {
            return "onedrive";
        }

        if (subKey.Contains("Device Metadata", StringComparison.OrdinalIgnoreCase))
        {
            return "device";
        }

        if (subKey.Contains("WindowsCopilot", StringComparison.OrdinalIgnoreCase))
        {
            return "copilot";
        }

        if (subKey.Contains("\\Edge", StringComparison.OrdinalIgnoreCase)
            || subKey.EndsWith("Edge", StringComparison.OrdinalIgnoreCase)
            || subKey.Contains("EdgeUpdate", StringComparison.OrdinalIgnoreCase)
            || subKey.Contains("Edge\\", StringComparison.OrdinalIgnoreCase))
        {
            return "edge";
        }

        return "policy";
    }
}

/// <summary>One offline <c>reg add</c> row under SOFTWARE or SYSTEM hive.</summary>
public sealed record OfflinePolicyRow(
    string Hive,
    string SubKey,
    string Name,
    string RegType,
    string Data,
    string Digest);

public sealed record DohProviderSpec(string Primary, string Secondary, string DohTemplate);
