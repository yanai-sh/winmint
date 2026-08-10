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
            advanced?.SetValue("HideFileExt", 0, RegistryValueKind.DWord);
            advanced?.SetValue("Hidden", 1, RegistryValueKind.DWord);
            advanced?.SetValue("FullPathAddress", 1, RegistryValueKind.DWord);
            advanced?.SetValue("LaunchTo", 1, RegistryValueKind.DWord);
            advanced?.SetValue("ShowFrequent", 0, RegistryValueKind.DWord);
            advanced?.SetValue("NavPaneShowVersionControl", 1, RegistryValueKind.DWord);
            advanced?.SetValue("ShowSyncProviderNotifications", 0, RegistryValueKind.DWord);
            advanced?.SetValue("TaskbarDa", 0, RegistryValueKind.DWord);
            advanced?.SetValue("TaskbarEndTask", 1, RegistryValueKind.DWord);
            advanced?.SetValue("Start_IrisRecommendations", 0, RegistryValueKind.DWord);
        }

        using (RegistryKey? explorer = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"))
        {
            explorer?.SetValue("ShowRecent", 0, RegistryValueKind.DWord);
            explorer?.SetValue("ShowCloudFilesInQuickAccess", 0, RegistryValueKind.DWord);
        }

        using (RegistryKey? searchPolicy = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Policies\Microsoft\Windows\Explorer"))
        {
            searchPolicy?.SetValue("DisableSearchBoxSuggestions", 1, RegistryValueKind.DWord);
        }

        using (RegistryKey? searchSettings = Registry.CurrentUser.CreateSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings"))
        {
            searchSettings?.SetValue("IsDynamicSearchBoxEnabled", 0, RegistryValueKind.DWord);
        }
    }
}
