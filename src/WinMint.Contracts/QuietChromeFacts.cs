namespace WinMint.Contracts;

/// <summary>
/// Always-on quiet / taskbar-chrome registry facts shared by offline ProductPosture stamp,
/// FirstLogon Apply, and Smoke S4 acceptance (ADR-009). Phase tags: offline-safe vs live-only.
/// </summary>
public static class QuietChromeFacts
{
    public const int SearchboxTaskbarMode = 0;
    public const int HideRecycleBin = 1;
    public const int SpotlightEnabledState = 0;
    public const int ExpectedDevMode = 1;
    public const int ExpectedSudo = 3;
    public const int ExpectedLongPaths = 1;

    /// <summary>HKLM AllowNewsAndInterests (NewsAndInterests CSP) — supported Widgets off.</summary>
    public const int ExpectedAllowNewsAndInterests = 0;

    public const string RecycleBinClsid = "{645FF040-5081-101B-9F08-00AA002F954E}";

    public static readonly IReadOnlyList<string> HideDesktopIconViews = ["NewStartPanel", "ClassicStartMenu"];

    /// <summary>Explorer\Advanced DWords (full set). Live-only subset is skipped during offline NTUSER stamp and deferred to shell.chrome.</summary>
    public static readonly IReadOnlyDictionary<string, int> ExplorerAdvancedDwords =
        new Dictionary<string, int>(StringComparer.Ordinal)
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

    /// <summary>
    /// Taskbar Advanced keys owned by shell.chrome after packages (OOBE rewrites if set during workstation.quiet;
    /// NTUSER stamp fails on Win11 for these). Best-effort stamp + RunOnce re-stamp.
    /// </summary>
    public static readonly IReadOnlySet<string> LiveOnlyTaskbarExplorerAdvanced =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "TaskbarDa",
            "TaskbarMn",
            "ShowTaskViewButton",
            "ShowCopilotButton",
        };

    /// <summary>
    /// Live-only keys the 25H2 shell may delete after Autologon; product posture is the matching HKLM policy
    /// (Widgets → AllowNewsAndInterests). Not required for VerifyFinalChrome / Smoke live quiet asserts.
    /// </summary>
    public static readonly IReadOnlySet<string> PolicyOwnedTaskbarExplorerAdvanced =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "TaskbarDa",
        };

    public static readonly IReadOnlyList<string> ContentDeliveryManagerDwords =
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

    /// <summary>Baseline Start pin ids Smoke asserts (matches GuestChrome StartPinsBaselineJson).</summary>
    public static readonly IReadOnlyList<string> RequiredStartPinIds = ["explorer", "settings", "terminal"];

    /// <summary>Baseline taskbar pin ids Smoke asserts (matches GuestChrome TaskbarLayoutBaselineXml).</summary>
    public static readonly IReadOnlyList<string> RequiredTaskbarPinIds = ["explorer", "terminal"];

    /// <summary>
    /// Live quiet DWords Smoke asserts after shell.chrome (subset of ExplorerAdvanced + Search).
    /// Policy-owned Advanced keys (Widgets TaskbarDa) are omitted — assert HKLM policy instead.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, int> RequiredQuietDwords =
        new Dictionary<string, int>(StringComparer.Ordinal)
        {
            ["SearchboxTaskbarMode"] = SearchboxTaskbarMode,
            ["TaskbarMn"] = 0,
            ["ShowTaskViewButton"] = 0,
            ["ShowCopilotButton"] = 0,
        };
}
