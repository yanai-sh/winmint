using System.Collections.Frozen;

using WinMint.Contracts;

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
    public const string YasbWingetId = PackageIds.Yasb;
    public const string KomorebiWingetId = PackageIds.Komorebi;
    public const string WhkdWingetId = "LGUG2Z.whkd";

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

    /// <summary>v1 groups coreMicrosoft, communication, gaming, consumerThirdParty, oemConsumer, plus WhatsApp.</summary>
    public static IReadOnlyList<string> AppxIds { get; } =
    [
        "Microsoft.GetHelp",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.549981C3F5F10",
        "MicrosoftCorporationII.MicrosoftFamily",
        "Microsoft.StartExperiencesApp",
        "Microsoft.BingSearch",
        "Microsoft.BingFinance",
        "Microsoft.BingFoodAndDrink",
        "Microsoft.BingHealthAndFitness",
        "Microsoft.BingNews",
        "Microsoft.BingSports",
        "Microsoft.BingTranslator",
        "Microsoft.BingTravel",
        "Microsoft.BingWeather",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftPowerBIForWindows",
        "Microsoft.MixedReality.Portal",
        "Microsoft.NetworkSpeedTest",
        "Microsoft.Office.OneNote",
        "Microsoft.Office.Sway",
        "Microsoft.OutlookForWindows",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.RemoteDesktop",
        "Microsoft.RemoteDesktopPreview",
        "Microsoft.SkypeApp",
        "Microsoft.Todos",
        "Microsoft.Wallet",
        "Microsoft.Whiteboard",
        "Microsoft.Windows.AIHub",
        "Microsoft.Windows.DevHome",
        "Microsoft.Windows.PeopleExperienceHost",
        "Microsoft.WindowsMaps",
        "Microsoft.WindowsPhone",
        "Microsoft.WindowsReadingList",
        "MicrosoftWindows.Client.WebExperience",
        "Microsoft.Copilot",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Clipchamp.Clipchamp",
        "Windows.CBSPreview",
        "Microsoft.WindowsCalculator",
        "MicrosoftCorporationII.QuickAssist",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.MicrosoftStickyNotes",
        "MSTeams",
        "MicrosoftTeams",
        "Microsoft.People",
        "Microsoft.windowscommunicationsapps",
        "Microsoft.Messaging",
        "Microsoft.OneConnect",
        "Microsoft.CommsPhone",
        "Microsoft.ConnectivityStore",
        "Microsoft.GamingApp",
        "Microsoft.XboxApp",
        "Microsoft.XboxGameOverlay",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.Xbox.TCUI",
        "Spotify",
        "SpotifyAB.SpotifyMusic",
        "TikTok",
        "BytedancePte.Ltd.TikTok",
        "Netflix",
        "4DF9E0F8.Netflix",
        "Disney",
        "DisneyMagicKingdoms",
        "A278AB0D.DisneyMagicKingdoms",
        "Amazon.com.Amazon",
        "AmazonVideo.PrimeVideo",
        "Facebook",
        "Facebook.Facebook",
        "Facebook.InstagramBeta",
        "Instagram",
        "LinkedInforWindows",
        "Twitter",
        "XING",
        "XINGAG.XING",
        "Flipboard",
        "HULULLC.HULUPLUS",
        "PicsArt",
        "Duolingo-LearnLanguagesforFree",
        "D5EA27B7.Duolingo-LearnLanguagesforFree",
        "king.com",
        "HiddenCity",
        "FarmVille2CountryEscape",
        "MarchofEmpires",
        "Royal Revolt",
        "KeeperSecurityInc.Keeper",
        "WinZipComputing.WinZipUniversal",
        "McAfee",
        "NortonLifeLock",
        "NortonSecurity",
        "ExpressVPN",
        "Surfshark",
        "SurfsharkVPN",
        "AVGTechnologies",
        "AvastSoftware",
        "KasperskyLab",
        "DolbyLaboratories",
        "Piriform.CCleaner",
        "AD2F1837.HPAIExperienceCenter",
        "AD2F1837.HPConnectedMusic",
        "AD2F1837.HPConnectedPhotopoweredbySnapfish",
        "AD2F1837.HPJumpStarts",
        "AD2F1837.HPRegistration",
        "AD2F1837.HPWelcome",
        "AD2F1837.HPWorkWell",
        "DellInc.DellDigitalDelivery",
        "DellInc.DellMobileConnect",
        "E046963F.LenovoCompanion",
        "5319275A.WhatsAppDesktop",
    ];

    /// <summary>v1 preserve plus systemExemptPrefixes (Clock, Store, Camera, OEM support, CBS, …).</summary>
    public static IReadOnlyList<string> PreserveAppx { get; } =
    [
        "Microsoft.WindowsStore",
        "Microsoft.StorePurchaseApp",
        "Microsoft.DesktopAppInstaller",
        "Microsoft.SecHealthUI",
        "Microsoft.Edge",
        "Microsoft.EdgeWebView",
        "Microsoft.WebView2",
        "Microsoft.WindowsCamera",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsNotepad",
        "Microsoft.ScreenSketch",
        "Microsoft.Windows.Photos",
        "Microsoft.Paint",
        "AD2F1837.HPSystemInformation",
        "AD2F1837.HPPrivacySettings",
        "AD2F1837.HPSupportAssistant",
        "DellInc.DellCommandUpdate",
        "DellInc.DellPowerManager",
        "E046963F.LenovoSettings",
        "E046963F.LenovoVantage",
        "Microsoft.Windows.PeopleExperienceHost",
        "Windows.CBSPreview",
        "Microsoft.XboxGameCallableUI",
        "Microsoft.Windows.ParentalControls",
        "MicrosoftWindows.Client.CBS",
    ];

    public static IReadOnlySet<string> PreserveAppxSet { get; } =
        PreserveAppx.ToFrozenSet(StringComparer.OrdinalIgnoreCase);

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
        [.. ComposePolicies(includeBraveDebloat: false, includeDriverHygiene: false)
            .Select(static row => row.Digest)
            .Distinct(StringComparer.Ordinal)];

    /// <summary>Profile ∪ product strip, minus preserve/exempt; case-insensitive dedupe.</summary>
    public static IReadOnlyList<string> UnionAppx(IReadOnlyList<string> profileAppx) =>
        [.. IdList.UnionOrdered(profileAppx, AppxIds)
            .Where(id => !PreserveAppxSet.Contains(id))];

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

    /// <summary>HKCU quiet defaults for Default User NTUSER.DAT. Never includes Policies keys.</summary>
    public static IReadOnlyList<OfflinePolicyRow> ComposeDefaultUserRows()
    {
        List<OfflinePolicyRow> rows =
        [
            User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", "0"),
            User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", "0"),
            User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings", "NOC_GLOBAL_SETTING_TOASTS_ENABLED", "0"),
        ];
        foreach ((string name, int value) in DefaultUserExplorerAdvanced)
        {
            if (DefaultUserOfflineSkipExplorerAdvanced.Contains(name))
            {
                continue;
            }

            rows.Add(User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced", name, value.ToString(System.Globalization.CultureInfo.InvariantCulture)));
        }

        rows.Add(User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer", "ShowRecent", "0"));
        rows.Add(User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer", "ShowCloudFilesInQuickAccess", "0"));
        rows.Add(User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Search", "SearchboxTaskbarMode", "0"));
        foreach (string view in DefaultUserHideDesktopIconViews)
        {
            rows.Add(User(
                $@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\{view}",
                RecycleBinClsid,
                "1"));
        }

        foreach (string name in DefaultUserContentDeliveryManager)
        {
            rows.Add(User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager", name, "0"));
        }

        rows.Add(User(@"SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings", "IsDynamicSearchBoxEnabled", "0"));
        rows.Add(UserString(@"Control Panel\Desktop", "Wallpaper", GuestChrome.BloomWallpaperPath));
        rows.Add(UserString(@"Control Panel\Desktop", "WallpaperStyle", "10"));
        rows.Add(UserString(@"Control Panel\Desktop", "TileWallpaper", "0"));
        return rows;
    }

    public static IReadOnlyList<OfflinePolicyRow> ComposePolicies(
        bool includeBraveDebloat,
        bool includeDriverHygiene = false)
    {
        List<OfflinePolicyRow> rows =
        [
            // Widgets first in the JSON only for readability. Unauthorized Dsh writes were the
            // load-key name WinMintPol_SOFTWARE, not row order.
            Soft("Policies\\Microsoft\\Dsh", "AllowNewsAndInterests", "0", "widgets"),
            SoftString(
                "Policies\\Microsoft\\Windows\\Explorer",
                "ConfigureStartPins",
                GuestChrome.StartPinsBaselineJson,
                "start"),
            Soft("Policies\\Microsoft\\Windows\\Explorer", "DisableSearchBoxSuggestions", "1", "search"),
            SoftString(
                @"Microsoft\Windows\CurrentVersion\Explorer",
                "LayoutXMLPath",
                GuestChrome.TaskbarLayoutOemGuestPath,
                "taskbar"),
            SoftString(@"Microsoft\Windows NT\CurrentVersion\Fonts", "Cascadia Code NF (TrueType)", "CascadiaCodeNF.ttf", "fonts"),
            SoftString(@"Microsoft\Windows NT\CurrentVersion\Fonts", "Cascadia Mono NF (TrueType)", "CascadiaMonoNF.ttf", "fonts"),
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

        return [.. rows];
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

    private const string RecycleBinClsid = "{645FF040-5081-101B-9F08-00AA002F954E}";

    private static readonly string[] DefaultUserHideDesktopIconViews = ["NewStartPanel", "ClassicStartMenu"];

    // Values also in Win32WorkstationQuiet.ExplorerAdvancedDwords; taskbar subset is live-only (NTUSER stamp fails on Win11).
    private static readonly HashSet<string> DefaultUserOfflineSkipExplorerAdvanced =
        new(StringComparer.Ordinal)
        {
            "TaskbarDa",
            "TaskbarMn",
            "ShowTaskViewButton",
            "ShowCopilotButton",
        };

    private static readonly Dictionary<string, int> DefaultUserExplorerAdvanced =
        new(StringComparer.Ordinal)
        {
            ["HideFileExt"] = 0,
            ["Hidden"] = 1,
            ["FullPathAddress"] = 1,
            ["LaunchTo"] = 1,
            ["ShowFrequent"] = 0,
            ["NavPaneShowVersionControl"] = 1,
            ["ShowSyncProviderNotifications"] = 0,
            ["TaskbarDa"] = 0,
            ["TaskbarEndTask"] = 1,
            ["Start_IrisRecommendations"] = 0,
            ["ShowTaskViewButton"] = 0,
            ["TaskbarMn"] = 0,
            ["ShowCopilotButton"] = 0,
            ["Start_AccountNotifications"] = 0,
        };

    private static readonly string[] DefaultUserContentDeliveryManager =
    [
        "SubscribedContent-310093Enabled",
        "SubscribedContent-338388Enabled",
        "SubscribedContent-338389Enabled",
        "SubscribedContent-338393Enabled",
        "SubscribedContent-353694Enabled",
        "SubscribedContent-353696Enabled",
        "SubscribedContent-353698Enabled",
        "SoftLandingEnabled",
        "SystemPaneSuggestionsEnabled",
        "SilentInstalledAppsEnabled",
        "PreInstalledAppsEnabled",
        "OemPreInstalledAppsEnabled",
        "RotatingLockScreenEnabled",
        "RotatingLockScreenOverlayEnabled",
    ];

    /// <summary>
    /// Machine posture aligned with Microsoft Windows Developer Config (HKLM only).
    /// Skip RDP enable — widens attack surface on wipe-ready workstations.
    /// </summary>
    private static readonly OfflinePolicyRow[] WorkstationMachine =
    [
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
        Soft(@"Microsoft\OneDrive", "PreventNetworkTrafficPreUserSignIn", "1", "onedrive"),
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

    private static OfflinePolicyRow User(string subKey, string name, string data) =>
        new("NTUSER", subKey, name, "REG_DWORD", data, "quiet");

    private static OfflinePolicyRow UserString(string subKey, string name, string data) =>
        new("NTUSER", subKey, name, "REG_SZ", data, "quiet");
}

/// <summary>One offline <c>reg add</c> row under SOFTWARE, SYSTEM, or NTUSER. <see cref="Family"/> is declared, never inferred.</summary>
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
