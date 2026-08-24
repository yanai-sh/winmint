using System.Security;

namespace WinMint.Provisioning;

public static class ShellChromeLayout
{
    public const string WallpaperPath = @"C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg";
    internal const string CursorWingetId = "Anysphere.Cursor";
    internal const string ZenWingetId = "Zen-Team.Zen-Browser";

    public static string ConfigureStartPinsJson(IReadOnlyList<string> desktopLinkPaths)
    {
        ArgumentNullException.ThrowIfNull(desktopLinkPaths);
        List<string> items =
        [
            """{"desktopAppId":"Microsoft.Windows.Explorer"}""",
            """{"packagedAppId":"windows.immutablecontrolpanel"}""",
            """{"packagedAppId":"Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"}""",
        ];
        foreach (string path in desktopLinkPaths)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                continue;
            }

            items.Add($$"""{"desktopAppLink":{{JsonString(path)}}}""");
        }

        return $$"""{"pinnedList":[{{string.Join(",", items)}}]}""";
    }

    public static string TaskbarLayoutXml(IReadOnlyList<string> desktopLinkPaths)
    {
        ArgumentNullException.ThrowIfNull(desktopLinkPaths);
        List<string> lines =
        [
            """<?xml version="1.0" encoding="utf-8"?>""",
            "<LayoutModificationTemplate",
            """"" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification""""",
            """"" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout""""",
            """"" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout""""",
            """"" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout""""",
            """ Version="1">""",
            """  <CustomTaskbarLayoutCollection PinListPlacement="Replace">""",
            "    <defaultlayout:TaskbarLayout>",
            "      <taskbar:TaskbarPinList>",
            """        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />""",
            """        <taskbar:UWA AppUserModelID="Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" />""",
        ];
        foreach (string path in desktopLinkPaths)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                continue;
            }

            string escaped = SecurityElement.Escape(path) ?? path;
            lines.Add($"""        <taskbar:DesktopApp DesktopApplicationLinkPath="{escaped}" />""");
        }

        lines.Add("      </taskbar:TaskbarPinList>");
        lines.Add("    </defaultlayout:TaskbarLayout>");
        lines.Add("  </CustomTaskbarLayoutCollection>");
        lines.Add("</LayoutModificationTemplate>");
        return string.Join("\r\n", lines);
    }

    public static string? TryResolveShortcut(string wingetId)
    {
        if (string.IsNullOrWhiteSpace(wingetId))
        {
            return null;
        }

        foreach (string candidate in Candidates(wingetId))
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }

            string link = Path.ChangeExtension(candidate, ".lnk");
            if (File.Exists(link))
            {
                return link;
            }
        }

        return null;
    }

    private static string JsonString(string value) =>
        $"\"{value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal)}\"";

    internal static bool IsPinApp(string wingetId) => TryPinId(wingetId) is not null;

    internal static string? TryPinId(string wingetId)
    {
        if (wingetId.Equals(CursorWingetId, StringComparison.OrdinalIgnoreCase))
        {
            return "cursor";
        }

        if (wingetId.Equals(ZenWingetId, StringComparison.OrdinalIgnoreCase))
        {
            return "zen-browser";
        }

        return null;
    }

    private static string[] Candidates(string wingetId)
    {
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (wingetId.Equals(CursorWingetId, StringComparison.OrdinalIgnoreCase))
        {
            return
            [
                Path.Combine(localAppData, "Programs", "cursor", "Cursor.exe"),
                Path.Combine(localAppData, "Programs", "Cursor", "Cursor.exe"),
                Path.Combine(programFiles, "Cursor", "Cursor.exe"),
            ];
        }

        if (wingetId.Equals(ZenWingetId, StringComparison.OrdinalIgnoreCase))
        {
            return
            [
                Path.Combine(programFiles, "Zen Browser", "zen.exe"),
                Path.Combine(programFilesX86, "Zen Browser", "zen.exe"),
                Path.Combine(localAppData, "Programs", "Zen Browser", "zen.exe"),
            ];
        }

        return [];
    }
}
