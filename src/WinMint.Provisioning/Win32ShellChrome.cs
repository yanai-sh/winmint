using System.Runtime.Versioning;
using System.Text.Json;

using Microsoft.Win32;

using Windows.Win32;
using Windows.Win32.UI.WindowsAndMessaging;

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
    /// Live desktop still shows bloom + search hide (explorer first-run can overwrite after Apply).
    /// </summary>
    public static bool IsLiveSticky() => VerifyFinalChrome(wallpaperPresent: true);

    /// <summary>Fail-closed gate before unlock — bloom/search/Spotlight must stick.</summary>
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
        return mode is int searchMode && searchMode == Win32WorkstationQuiet.SearchboxTaskbarMode;
    }

    private static void WriteEvidence(IReadOnlyList<string> startPinIds, IReadOnlyList<string> taskbarPinIds)
    {
        Dictionary<string, int> quiet = new(Win32WorkstationQuiet.ExplorerAdvancedDwords, StringComparer.Ordinal)
        {
            ["SearchboxTaskbarMode"] = Win32WorkstationQuiet.SearchboxTaskbarMode,
        };

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
}
