using System.Diagnostics;
using System.Runtime.Versioning;

using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon quiet defaults aligned with Microsoft Windows Developer Config (HKCU + dark.theme).
/// Best-effort: never throws to the job runner.
/// </summary>
[SupportedOSPlatform("windows")]
public static class Win32WorkstationQuiet
{
    public const string DarkThemePath = @"C:\Windows\Resources\Themes\dark.theme";

    public const int SearchboxTaskbarMode = 0;
    public const int HideRecycleBin = 1;

    private const string RecycleBinClsid = "{645FF040-5081-101B-9F08-00AA002F954E}";

    private static readonly string[] HideDesktopIconViews = ["NewStartPanel", "ClassicStartMenu"];

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

    // v1 Set-WinMintFirstLogonQuietUxDefaults ContentDeliveryManager names, all 0.
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

    public static void Apply()
    {
        try
        {
            ApplyDarkTheme();
        }
        catch
        {
            // Best-effort — registry DWords below still apply.
        }

        try
        {
            ApplyUserRegistry();
        }
        catch
        {
            // Best-effort product constant.
        }
    }

    private static void ApplyDarkTheme()
    {
        // Microsoft Dev Config: apply the shipped .theme so apps + system + accents flip together.
        if (!File.Exists(DarkThemePath))
        {
            return;
        }

        // Shell-open .theme (UseShellExecute) — Process.Run rejects shell execute, same as UAC runas.
        using Process? process = Process.Start(
            new ProcessStartInfo
            {
                FileName = DarkThemePath,
                UseShellExecute = true,
            });
        _ = process?.WaitForExit(TimeSpan.FromSeconds(8));
    }

    private static void ApplyUserRegistry()
    {
        // Widgets / News and interests: ISO stamps HKLM Dsh first; live overlay if that row missed.
        try
        {
            using RegistryKey? existing = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\Microsoft\Dsh");
            object? current = existing?.GetValue("AllowNewsAndInterests");
            if (current is not int value || value != 0)
            {
                using RegistryKey? dsh = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Policies\Microsoft\Dsh");
                dsh?.SetValue("AllowNewsAndInterests", 0, RegistryValueKind.DWord);
            }
        }
        catch
        {
            // Best-effort — continue HKCU quiet rows.
        }

        // Theme DWords as belt-and-suspenders when .theme flash is flaky.
        using (RegistryKey? personalize = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
        {
            personalize?.SetValue("AppsUseLightTheme", 0, RegistryValueKind.DWord);
            personalize?.SetValue("SystemUsesLightTheme", 0, RegistryValueKind.DWord);
        }

        // Global Do Not Disturb / toasts off.
        using (RegistryKey? toasts = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"))
        {
            toasts?.SetValue("NOC_GLOBAL_SETTING_TOASTS_ENABLED", 0, RegistryValueKind.DWord);
        }

        using (RegistryKey? advanced = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"))
        {
            if (advanced is not null)
            {
                foreach ((string name, int value) in ExplorerAdvancedDwords)
                {
                    advanced.SetValue(name, value, RegistryValueKind.DWord);
                }
            }
        }

        using (RegistryKey? explorer = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"))
        {
            explorer?.SetValue("ShowRecent", 0, RegistryValueKind.DWord);
            explorer?.SetValue("ShowCloudFilesInQuickAccess", 0, RegistryValueKind.DWord);
        }

        using (RegistryKey? search = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Search"))
        {
            search?.SetValue("SearchboxTaskbarMode", SearchboxTaskbarMode, RegistryValueKind.DWord);
        }

        foreach (string view in HideDesktopIconViews)
        {
            using RegistryKey? hide = Registry.CurrentUser.CreateSubKey(
                $@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\{view}");
            hide?.SetValue(RecycleBinClsid, HideRecycleBin, RegistryValueKind.DWord);
        }

        using (RegistryKey? cdm = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"))
        {
            if (cdm is not null)
            {
                foreach (string name in ContentDeliveryManagerDwords)
                {
                    cdm.SetValue(name, 0, RegistryValueKind.DWord);
                }
            }
        }

        using (RegistryKey? searchSettings = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings"))
        {
            searchSettings?.SetValue("IsDynamicSearchBoxEnabled", 0, RegistryValueKind.DWord);
        }
    }
}
