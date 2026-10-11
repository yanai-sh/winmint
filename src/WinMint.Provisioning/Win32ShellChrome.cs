using System.Runtime.Versioning;
using System.Text.Json;

using Microsoft.Win32;

using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

using WinMint.Contracts;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows10.0.19041.0")]
public static class Win32ShellChrome
{
    public static bool Apply(ShellChromeRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        bool wallpaperPresent = File.Exists(ShellChromeLayout.WallpaperPath);
        if (!wallpaperPresent && !request.FailOpen)
        {
            return false;
        }

        if (!ShellChromeLayout.TryBuildPins(
                request.SelectedWingetIds,
                request.FailOpen || !request.RequireSelectedPins,
                ShellChromeLayout.TryResolveShortcut,
                out ShellChromePins pins))
        {
            return false;
        }

        string step = "begin";
        try
        {
            // Spotlight + OOBE taskbar chrome win if applied before bloom/pins.
            step = "spotlight";
            Win32WorkstationQuiet.DisableDesktopSpotlight();
            if (wallpaperPresent)
            {
                step = "wallpaper";
                ApplyWallpaper();
            }

            step = "pins";
            ApplyPins(pins.LinkPaths);
            step = "taskbar.LiveOnly";
            Win32WorkstationQuiet.ApplyTaskbarChrome();
            step = "verify";
            if (!VerifyFinalChrome(wallpaperPresent) && !request.FailOpen)
            {
                return false;
            }

            step = "evidence";
            WriteEvidence(pins.StartPinIds, pins.TaskbarPinIds);
            return true;
        }
        catch (Exception ex) when (ex is not OperationCanceledException && request.FailOpen)
        {
            return true;
        }
        catch (Exception ex) when (ex is not OperationCanceledException && !request.FailOpen)
        {
            throw new InvalidOperationException($"{step}: {ex.Message}", ex);
        }
    }

    private static void ApplyWallpaper()
    {
        using (RegistryKey? desktop = Registry.CurrentUser.CreateSubKey(@"Control Panel\Desktop"))
        {
            desktop?.SetValue("Wallpaper", ShellChromeLayout.WallpaperPath, RegistryValueKind.String);
            desktop?.SetValue("WallpaperStyle", "10", RegistryValueKind.String);
            desktop?.SetValue("TileWallpaper", "0", RegistryValueKind.String);
        }

        // ponytail: explorer first-run may keep a stale transcode of img19; drop so SPI sticks.
        try
        {
            string transcoded = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Microsoft",
                "Windows",
                "Themes",
                "TranscodedWallpaper");
            if (File.Exists(transcoded))
            {
                File.Delete(transcoded);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Best-effort — registry + SPI still apply.
        }

        unsafe
        {
            fixed (char* wallpaper = ShellChromeLayout.WallpaperPath)
            {
                _ = PInvoke.SystemParametersInfo(
                    SYSTEM_PARAMETERS_INFO_ACTION.SPI_SETDESKWALLPAPER,
                    0,
                    wallpaper,
                    SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS.SPIF_UPDATEINIFILE
                    | SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS.SPIF_SENDCHANGE);
            }
        }
    }

    private static void ApplyPins(IReadOnlyList<string> desktopLinkPaths)
    {
        string shellDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "Windows",
            "Shell");
        Directory.CreateDirectory(shellDir);
        File.WriteAllText(
            Path.Combine(shellDir, "LayoutModification.xml"),
            ShellChromeLayout.TaskbarLayoutXml(desktopLinkPaths));

        // ponytail: LayoutModification is ignored once Taskband exists (OOBE explorer). Clear so Unlock re-reads Replace list.
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(
                @"Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband",
                throwOnMissingSubKey: false);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or SystemException)
        {
            // Best-effort — OEM LayoutXMLPath still covers new profiles.
        }
    }

    /// <summary>
    /// Live desktop still shows bloom + search hide + live-only taskbar quiet
    /// (explorer first-run can overwrite after Apply).
    /// </summary>
    public static bool IsLiveSticky() => VerifyFinalChrome(wallpaperPresent: true);

    /// <summary>Fail-closed gate — bloom/search/Spotlight/Widgets-class taskbar keys must stick.</summary>
    private static bool VerifyFinalChrome(bool wallpaperPresent)
    {
        if (wallpaperPresent)
        {
            using RegistryKey? desktop = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop");
            string? wallpaper = desktop?.GetValue("Wallpaper") as string;
            if (!string.Equals(wallpaper, ShellChromeLayout.WallpaperPath, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        using (RegistryKey? spotlight = Registry.CurrentUser.OpenSubKey(
                   @"SOFTWARE\Microsoft\Windows\CurrentVersion\DesktopSpotlight\Settings"))
        {
            object? enabled = spotlight?.GetValue("EnabledState");
            if (enabled is int state && state != 0)
            {
                return false;
            }
        }

        using RegistryKey? search = Registry.CurrentUser.OpenSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Search");
        object? mode = search?.GetValue("SearchboxTaskbarMode");
        if (mode is not int searchMode || searchMode != Win32WorkstationQuiet.SearchboxTaskbarMode)
        {
            return false;
        }

        // Live-only Advanced keys Smoke still asserts — skip policy-owned (Widgets TaskbarDa may vanish).
        using RegistryKey? advanced = Registry.CurrentUser.OpenSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced");
        foreach (string name in QuietChromeFacts.LiveOnlyTaskbarExplorerAdvanced)
        {
            if (QuietChromeFacts.PolicyOwnedTaskbarExplorerAdvanced.Contains(name))
            {
                continue;
            }

            if (!QuietChromeFacts.ExplorerAdvancedDwords.TryGetValue(name, out int want))
            {
                continue;
            }

            if (advanced?.GetValue(name) is not int actual || actual != want)
            {
                return false;
            }
        }

        return true;
    }

    private static void WriteEvidence(IReadOnlyList<string> startPinIds, IReadOnlyList<string> taskbarPinIds)
    {
        // Live reads only — never invent expected dwords when unset (policy-owned keys may be absent).
        Dictionary<string, int> quiet = new(StringComparer.Ordinal);
        foreach ((string name, _) in QuietChromeFacts.RequiredQuietDwords)
        {
            if (TryReadRequiredQuietDword(name) is int got)
            {
                quiet[name] = got;
            }
        }

        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint");
        byte[] utf8 = JsonSerializer.SerializeToUtf8Bytes(
            new ShellChromeEvidenceFile(
                ShellChromeEvidenceFile.SchemaVersionValue,
                ShellChromeLayout.WallpaperPath,
                [.. startPinIds],
                [.. taskbarPinIds],
                quiet),
            ProvisioningJsonContext.Default.ShellChromeEvidenceFile);
        string path = Path.Combine(dir, "shell-chrome.json");

        // ponytail: medium-IL can briefly deny ProgramData; verify already passed — retry once.
        for (int attempt = 0; ; attempt++)
        {
            try
            {
                Directory.CreateDirectory(dir);
                File.WriteAllBytes(path, utf8);
                return;
            }
            catch (Exception ex) when (
                attempt == 0
                && ex is UnauthorizedAccessException or IOException)
            {
                Thread.Sleep(250);
            }
        }
    }

    private static int? TryReadRequiredQuietDword(string name)
    {
        if (string.Equals(name, "SearchboxTaskbarMode", StringComparison.Ordinal))
        {
            using RegistryKey? search = Registry.CurrentUser.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Search");
            return search?.GetValue(name) as int?;
        }

        using RegistryKey? advanced = Registry.CurrentUser.OpenSubKey(
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced");
        return advanced?.GetValue(name) as int?;
    }
}
