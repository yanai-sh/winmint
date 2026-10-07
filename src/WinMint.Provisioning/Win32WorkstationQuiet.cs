using System.Diagnostics;
using System.Runtime.Versioning;

using Microsoft.Win32;

using WinMint.Contracts;

namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon quiet defaults aligned with Microsoft Windows Developer Config (HKCU + dark.theme).
/// Theme/CDM/file UX only — taskbar search/Spotlight/bloom owned by <see cref="Win32ShellChrome"/>.
/// Registry facts: <see cref="QuietChromeFacts"/>. Best-effort: never throws to the job runner.
/// </summary>
[SupportedOSPlatform("windows")]
public static class Win32WorkstationQuiet
{
    public const string DarkThemePath = @"C:\Windows\Resources\Themes\dark.theme";

    public static int SearchboxTaskbarMode => QuietChromeFacts.SearchboxTaskbarMode;

    public static int HideRecycleBin => QuietChromeFacts.HideRecycleBin;

    public static IReadOnlyDictionary<string, int> ExplorerAdvancedDwords => QuietChromeFacts.ExplorerAdvancedDwords;

    public static IReadOnlyList<string> ContentDeliveryManagerDwords => QuietChromeFacts.ContentDeliveryManagerDwords;

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
                foreach ((string name, int value) in QuietChromeFacts.ExplorerAdvancedDwords)
                {
                    if (QuietChromeFacts.LiveOnlyTaskbarExplorerAdvanced.Contains(name))
                    {
                        continue;
                    }

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

        foreach (string view in QuietChromeFacts.HideDesktopIconViews)
        {
            using RegistryKey? hide = Registry.CurrentUser.CreateSubKey(
                $@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\{view}");
            hide?.SetValue(QuietChromeFacts.RecycleBinClsid, QuietChromeFacts.HideRecycleBin, RegistryValueKind.DWord);
        }

        using (RegistryKey? cdm = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"))
        {
            if (cdm is not null)
            {
                foreach (string name in QuietChromeFacts.ContentDeliveryManagerDwords)
                {
                    cdm.SetValue(name, 0, RegistryValueKind.DWord);
                }
            }
        }

        using RegistryKey? searchSettings = Registry.CurrentUser.CreateSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings");
        searchSettings?.SetValue("IsDynamicSearchBoxEnabled", 0, RegistryValueKind.DWord);
    }

    /// <summary>
    /// Taskbar search/widgets + Desktop Spotlight off. Owned by shell.chrome after packages.
    /// </summary>
    public static void ApplyTaskbarChrome()
    {
        using (RegistryKey? advanced = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"))
        {
            if (advanced is not null)
            {
                foreach (string name in QuietChromeFacts.LiveOnlyTaskbarExplorerAdvanced)
                {
                    if (QuietChromeFacts.ExplorerAdvancedDwords.TryGetValue(name, out int value))
                    {
                        advanced.SetValue(name, value, RegistryValueKind.DWord);
                    }
                }
            }
        }

        using (RegistryKey? search = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Search"))
        {
            search?.SetValue("SearchboxTaskbarMode", QuietChromeFacts.SearchboxTaskbarMode, RegistryValueKind.DWord);
        }

        DisableDesktopSpotlight();
    }

    public static void DisableDesktopSpotlight()
    {
        using (RegistryKey? spotlight = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings"))
        {
            spotlight?.SetValue("EnabledState", QuietChromeFacts.SpotlightEnabledState, RegistryValueKind.DWord);
        }

        // Picture wallpaper (not Spotlight slideshow).
        using RegistryKey? wallpapers = Registry.CurrentUser.CreateSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers");
        wallpapers?.SetValue("BackgroundType", 0, RegistryValueKind.DWord);
    }
}
