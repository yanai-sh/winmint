using WinMint.Contracts;
using WinMint.Provisioning;

namespace WinMint.Tests;

public class ShellChromeLayoutTests
{
    [Fact]
    public void Start_pins_json_contains_explorer_settings_and_terminal()
    {
        string json = ShellChromeLayout.ConfigureStartPinsJson([]);

        Assert.Equal(GuestChrome.StartPinsBaselineJson, json);
        Assert.Contains("Microsoft.Windows.Explorer", json, StringComparison.Ordinal);
        Assert.Contains("windows.immutablecontrolpanel", json, StringComparison.Ordinal);
        Assert.Contains("Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", json, StringComparison.Ordinal);
    }

    [Fact]
    public void Taskbar_xml_is_replace_and_omits_xbox()
    {
        string xml = ShellChromeLayout.TaskbarLayoutXml([]);

        Assert.Equal(GuestChrome.TaskbarLayoutBaselineXml, xml);
        Assert.Contains("PinListPlacement=\"Replace\"", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("Microsoft.Xbox", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void TryResolveShortcut_prefers_lnk_when_exe_also_exists()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-chrome-lnk-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string exe = Path.Combine(dir, "Cursor.exe");
            string link = Path.Combine(dir, "Cursor.lnk");
            File.WriteAllBytes(exe, [0]);
            File.WriteAllBytes(link, [0]);

            Assert.Equal(link, ShellChromeLayout.TryResolveShortcut([exe]));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void TryResolveShortcut_uses_start_menu_lnk_when_sibling_missing()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-chrome-start-" + Guid.NewGuid().ToString("N"));
        string programs = Path.Combine(root, "Programs");
        Directory.CreateDirectory(programs);
        try
        {
            string exe = Path.Combine(root, "Cursor.exe");
            string startLink = Path.Combine(programs, "Cursor.lnk");
            File.WriteAllBytes(exe, [0]);
            File.WriteAllBytes(startLink, [0]);

            Assert.Equal(
                startLink,
                ShellChromeLayout.TryResolveShortcut([exe], startMenuRoots: [root], startMenuNameContains: "Cursor"));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void TryResolveShortcut_returns_null_when_only_exe_exists()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-chrome-exeonly-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string exe = Path.Combine(dir, "Cursor.exe");
            File.WriteAllBytes(exe, [0]);

            Assert.Null(ShellChromeLayout.TryResolveShortcut(
                [exe],
                startMenuRoots: [dir],
                startMenuNameContains: "Cursor"));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void TryBuildPins_omits_cursor_and_zen_when_no_lnk()
    {
        bool ok = ShellChromeLayout.TryBuildPins(
            [PackageIds.Cursor, PackageIds.ZenBrowser],
            failOpen: true,
            resolveShortcut: static _ => null,
            out ShellChromePins pins);

        Assert.True(ok);
        Assert.Empty(pins.LinkPaths);
        Assert.Equal(["explorer", "settings", "terminal"], pins.StartPinIds);
        Assert.Equal(["explorer", "terminal"], pins.TaskbarPinIds);
        Assert.DoesNotContain("cursor", pins.StartPinIds);
        Assert.DoesNotContain("zen-browser", pins.StartPinIds);
    }

    [Fact]
    public void TryBuildPins_fail_closed_when_selected_pin_has_no_lnk()
    {
        Assert.False(ShellChromeLayout.TryBuildPins(
            [PackageIds.Cursor],
            failOpen: false,
            resolveShortcut: static _ => null,
            out _));
    }

    [Fact]
    public void Zen_candidates_include_localappdata_zen_browser()
    {
        string expected = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Zen Browser",
            "zen.exe");

        Assert.Contains(expected, ShellChromeLayout.Candidates(PackageIds.ZenBrowser));
        Assert.Contains(
            Path.Combine(ShellChromeLayout.ZenUserInstallDirectory(), "zen.exe"),
            ShellChromeLayout.Candidates(PackageIds.ZenBrowser));
    }
}
