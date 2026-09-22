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

        try
        {
            if (wallpaperPresent)
            {
                ApplyWallpaper();
            }

            ApplyPins(pins.LinkPaths);
            WriteEvidence(pins.StartPinIds, pins.TaskbarPinIds);
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
            desktop?.SetValue("TileWallpaper", "0", RegistryValueKind.String);
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
