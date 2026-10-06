using System.Security;

using WinMint.Contracts;

namespace WinMint.Provisioning;

internal readonly record struct ShellChromePins(
    IReadOnlyList<string> LinkPaths,
    IReadOnlyList<string> StartPinIds,
    IReadOnlyList<string> TaskbarPinIds);

public static class ShellChromeLayout
{
    public const string WallpaperPath = GuestChrome.BloomWallpaperPath;

    /// <summary>
    /// User-writable install root. FirstLogon is medium IL; Zen's winget manifest is machine scope only.
    /// </summary>
    internal static string ZenUserInstallDirectory() =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            "Zen Browser");

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
        if (desktopLinkPaths.All(string.IsNullOrWhiteSpace))
        {
            return GuestChrome.TaskbarLayoutBaselineXml;
        }

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
        return string.Join('\n', lines);
    }

    public static string? TryResolveShortcut(string wingetId)
    {
        if (string.IsNullOrWhiteSpace(wingetId))
        {
            return null;
        }

        return TryResolveShortcut(
            Candidates(wingetId),
            DefaultStartMenuRoots(),
            StartMenuNameContains(wingetId));
    }

    // ponytail: no IShellLink/COM; sibling .lnk, then Start Menu name match. Never treat exe as a pin.
    internal static string? TryResolveShortcut(
        IReadOnlyList<string> candidates,
        IReadOnlyList<string>? startMenuRoots = null,
        string? startMenuNameContains = null)
    {
        foreach (string candidate in candidates)
        {
            string link = Path.ChangeExtension(candidate, ".lnk");
            if (File.Exists(link))
            {
                return link;
            }
        }

        if (!string.IsNullOrWhiteSpace(startMenuNameContains) && startMenuRoots is { Count: > 0 })
        {
            return TryFindStartMenuLink(startMenuRoots, startMenuNameContains);
        }

        return null;
    }

    internal static bool TryBuildPins(
        IReadOnlyList<string> selectedWingetIds,
        bool failOpen,
        Func<string, string?> resolveShortcut,
        out ShellChromePins pins)
    {
        ArgumentNullException.ThrowIfNull(selectedWingetIds);
        ArgumentNullException.ThrowIfNull(resolveShortcut);

        List<string> links = [];
        List<string> startPinIds = ["explorer", "settings", "terminal"];
        List<string> taskbarPinIds = ["explorer", "terminal"];
        foreach (string wingetId in selectedWingetIds)
        {
            string? pinId = TryPinId(wingetId);
            if (pinId is null)
            {
                continue;
            }

            string? resolved = resolveShortcut(wingetId);
            if (resolved is null || !resolved.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase))
            {
                if (!failOpen)
                {
                    pins = default;
                    return false;
                }

                continue;
            }

            links.Add(resolved);
            startPinIds.Add(pinId);
            taskbarPinIds.Add(pinId);
        }

        pins = new ShellChromePins(links, startPinIds, taskbarPinIds);
        return true;
    }

    private static string? TryFindStartMenuLink(IReadOnlyList<string> roots, string nameContains)
    {
        foreach (string root in roots)
        {
            if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            {
                continue;
            }

            IEnumerable<string> files;
            try
            {
                files = Directory.EnumerateFiles(root, "*.lnk", SearchOption.AllDirectories);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or DirectoryNotFoundException or IOException)
            {
                continue;
            }

            foreach (string file in files)
            {
                if (Path.GetFileNameWithoutExtension(file)
                    .Contains(nameContains, StringComparison.OrdinalIgnoreCase))
                {
                    return file;
                }
            }
        }

        return null;
    }

    private static string[] DefaultStartMenuRoots() =>
    [
        Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
        Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
    ];

    private static string? StartMenuNameContains(string wingetId)
    {
        if (wingetId.Equals(PackageIds.Cursor, StringComparison.OrdinalIgnoreCase))
        {
            return "Cursor";
        }

        if (wingetId.Equals(PackageIds.ZenBrowser, StringComparison.OrdinalIgnoreCase))
        {
            return "Zen";
        }

        return null;
    }

    private static string JsonString(string value) =>
        $"\"{value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal)}\"";

    internal static bool IsPinApp(string wingetId) => TryPinId(wingetId) is not null;

    internal static string? TryPinId(string wingetId)
    {
        if (wingetId.Equals(PackageIds.Cursor, StringComparison.OrdinalIgnoreCase))
        {
            return "cursor";
        }

        if (wingetId.Equals(PackageIds.ZenBrowser, StringComparison.OrdinalIgnoreCase))
        {
            return "zen-browser";
        }

        return null;
    }

    internal static string[] Candidates(string wingetId)
    {
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (wingetId.Equals(PackageIds.Cursor, StringComparison.OrdinalIgnoreCase))
        {
            return
            [
                Path.Combine(localAppData, "Programs", "cursor", "Cursor.exe"),
                Path.Combine(localAppData, "Programs", "Cursor", "Cursor.exe"),
                Path.Combine(programFiles, "Cursor", "Cursor.exe"),
            ];
        }

        if (wingetId.Equals(PackageIds.ZenBrowser, StringComparison.OrdinalIgnoreCase))
        {
            return
            [
                Path.Combine(programFiles, "Zen Browser", "zen.exe"),
                Path.Combine(localAppData, "Zen Browser", "zen.exe"),
                Path.Combine(programFilesX86, "Zen Browser", "zen.exe"),
                Path.Combine(ZenUserInstallDirectory(), "zen.exe"),
            ];
        }

        return [];
    }
}
