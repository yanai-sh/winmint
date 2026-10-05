using WinMint.Provisioning;

namespace WinMint.Tests;

public class ShellDesktopLayoutTests
{
    [Fact]
    public void BuildKomorebiMonitorsJson_emits_four_bsp_workspaces_per_monitor()
    {
        string json = ShellDesktopLayout.BuildKomorebiMonitorsJson(2);
        Assert.Contains("\"winmint-1-1\"", json, StringComparison.Ordinal);
        Assert.Contains("\"winmint-1-4\"", json, StringComparison.Ordinal);
        Assert.Contains("\"winmint-2-1\"", json, StringComparison.Ordinal);
        Assert.Contains("\"winmint-2-4\"", json, StringComparison.Ordinal);
        Assert.Contains("\"layout\":\"BSP\"", json, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(false, "native")]
    [InlineData(true, "komorebi")]
    public void SelectYasbVariant_matches_komorebi_selection(bool komorebi, string expected) =>
        Assert.Equal(expected, ShellDesktopLayout.SelectYasbVariant(komorebi));

    [Fact]
    public void BuildDisplayIndexPreferencesJson_skips_empty_serials()
    {
        string json = ShellDesktopLayout.BuildDisplayIndexPreferencesJson(["ABC", null, ""]);
        Assert.Contains("\"0\":\"ABC\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("\"1\"", json, StringComparison.Ordinal);
        Assert.Equal("{}", ShellDesktopLayout.BuildDisplayIndexPreferencesJson([]));
    }

    [Fact]
    public void RenderKomorebiConfig_replaces_placeholders()
    {
        string rendered = ShellDesktopLayout.RenderKomorebiConfig(
            "monitors={{WINMINT_MONITORS_JSON}} prefs={{WINMINT_DISPLAY_INDEX_PREFERENCES_JSON}}",
            "[{}]",
            "{}");
        Assert.Equal("monitors=[{}] prefs={}", rendered);
    }
}
