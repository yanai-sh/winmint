using WinMint.Provisioning;

namespace WinMint.Tests;

public class ShellChromeLayoutTests
{
    [Fact]
    public void Start_pins_json_contains_explorer_settings_and_terminal()
    {
        string json = ShellChromeLayout.ConfigureStartPinsJson([]);

        Assert.Contains("Microsoft.Windows.Explorer", json, StringComparison.Ordinal);
        Assert.Contains("windows.immutablecontrolpanel", json, StringComparison.Ordinal);
        Assert.Contains("Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", json, StringComparison.Ordinal);
    }

    [Fact]
    public void Taskbar_xml_is_replace_and_omits_xbox()
    {
        string xml = ShellChromeLayout.TaskbarLayoutXml([]);

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
    public void Zen_candidates_include_localappdata_zen_browser()
    {
        string expected = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Zen Browser",
            "zen.exe");

        Assert.Contains(expected, ShellChromeLayout.Candidates(ShellChromeLayout.ZenWingetId));
    }
}
