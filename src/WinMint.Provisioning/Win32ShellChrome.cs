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

        List<string> links = [];
        List<string> startPinIds = ["explorer", "settings", "terminal"];
        List<string> taskbarPinIds = ["explorer", "terminal"];
        foreach (string wingetId in request.SelectedWingetIds)
        {
            string? pinId = ShellChromeLayout.TryPinId(wingetId);
            if (pinId is null)
            {
                continue;
            }

            string? resolved = ShellChromeLayout.TryResolveShortcut(wingetId);
            if (resolved is null)
            {
                if (!request.FailOpen)
                {
                    return false;
                }

                continue;
            }

            links.Add(resolved);
            startPinIds.Add(pinId);
            taskbarPinIds.Add(pinId);
        }

        try
        {
            if (wallpaperPresent)
            {
                ApplyWallpaper();
            }

            ApplyPins(links);
            WriteEvidence(startPinIds, taskbarPinIds);
            return true;
        }
        catch (Exception ex) when (ex is not OperationCanceledException && request.FailOpen)
        {
            return true;
        }
    }

    private static void ApplyWallpaper()
    {
        using (RegistryKey? desktop = Registry.CurrentUser.CreateSubKey(@"Control Panel\Desktop"))
        {
            desktop?.SetValue("Wallpaper", ShellChromeLayout.WallpaperPath, RegistryValueKind.String);
            desktop?.SetValue("WallpaperStyle", "10", RegistryValueKind.String);
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
        string startJson = ShellChromeLayout.ConfigureStartPinsJson(desktopLinkPaths);
        using (RegistryKey? hkcu = Registry.CurrentUser.CreateSubKey(@"Software\Policies\Microsoft\Windows\Explorer"))
        {
            hkcu?.SetValue("ConfigureStartPins", startJson, RegistryValueKind.String);
        }

        using (RegistryKey? hklm = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Policies\Microsoft\Windows\Explorer"))
        {
            hklm?.SetValue("ConfigureStartPins", startJson, RegistryValueKind.String);
        }

        string shellDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "Windows",
            "Shell");
        Directory.CreateDirectory(shellDir);
        File.WriteAllText(
            Path.Combine(shellDir, "LayoutModification.xml"),
            ShellChromeLayout.TaskbarLayoutXml(desktopLinkPaths));
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
        Directory.CreateDirectory(dir);
        ShellChromeEvidenceFile document = new(
            ShellChromeEvidenceFile.SchemaVersionValue,
            ShellChromeLayout.WallpaperPath,
            [.. startPinIds],
            [.. taskbarPinIds],
            quiet);
        File.WriteAllBytes(
            Path.Combine(dir, "shell-chrome.json"),
            JsonSerializer.SerializeToUtf8Bytes(document, ProvisioningJsonContext.Default.ShellChromeEvidenceFile));
    }
}
