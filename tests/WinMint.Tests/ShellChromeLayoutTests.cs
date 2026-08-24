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
}
