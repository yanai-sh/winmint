namespace WinMint.Tests;

public class DesktopAssetTests
{
    [Theory]
    [InlineData("native")]
    [InlineData("komorebi")]
    public void Yasb_variants_keep_the_curated_bar_contract(string variant)
    {
        string root = Path.Combine(TestRepo.Root, "payload", "desktop", "yasb", variant);
        string config = File.ReadAllText(Path.Combine(root, "config.yaml"));
        string css = File.ReadAllText(Path.Combine(root, "styles.css"));

        Assert.Contains("screens: [\"**\"]", config, StringComparison.Ordinal);
        Assert.Contains("height: 34", config, StringComparison.Ordinal);
        Assert.Contains("always_on_top: false", config, StringComparison.Ordinal);
        Assert.Contains("windows_app_bar: true", config, StringComparison.Ordinal);
        Assert.Contains("auto_hide: false", config, StringComparison.Ordinal);
        Assert.Contains("center: [\"taskbar\"]", config, StringComparison.Ordinal);
        Assert.Contains("monitor_exclusive: true", config, StringComparison.Ordinal);
        Assert.Contains("grouping: true", config, StringComparison.Ordinal);
        Assert.Contains("strict_filtering: true", config, StringComparison.Ordinal);
        Assert.Contains("enabled: false", config, StringComparison.Ordinal);
        Assert.Contains("use_hook: false", config, StringComparison.Ordinal);
        Assert.Contains("system_colors: true", config, StringComparison.Ordinal);
        Assert.Contains("@import \"yasb_colors.css\";", css, StringComparison.Ordinal);
        Assert.Contains("\"Segoe UI\"", css, StringComparison.Ordinal);
        Assert.Contains("\"Segoe Fluent Icons\"", css, StringComparison.Ordinal);
        Assert.Contains(@"\ue80f", config, StringComparison.Ordinal);
        Assert.Contains(@"\ue7e8", config, StringComparison.Ordinal);
        Assert.DoesNotContain("weather", config, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("api_key", config, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("launcher", config, StringComparison.OrdinalIgnoreCase);

        if (variant == "native")
        {
            Assert.Contains("windows_workspaces", config, StringComparison.Ordinal);
            Assert.DoesNotContain("komorebi_workspaces", config, StringComparison.Ordinal);
        }
        else
        {
            Assert.Contains("komorebi_workspaces", config, StringComparison.Ordinal);
            Assert.Contains("komorebi_active_layout", config, StringComparison.Ordinal);
            Assert.DoesNotContain("windows_workspaces", config, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void Komorebi_template_leaves_monitor_generation_as_one_deterministic_seam()
    {
        string template = File.ReadAllText(Path.Combine(
            TestRepo.Root, "payload", "desktop", "komorebi", "komorebi.json.template"));

        Assert.Contains("\"default_workspace_padding\": 8", template, StringComparison.Ordinal);
        Assert.Contains("\"default_container_padding\": 8", template, StringComparison.Ordinal);
        Assert.Contains("\"border\": false", template, StringComparison.Ordinal);
        Assert.Contains("\"transparency\": false", template, StringComparison.Ordinal);
        Assert.Contains("\"enabled\": false", template, StringComparison.Ordinal);
        Assert.Contains("\"focus_follows_mouse\": false", template, StringComparison.Ordinal);
        Assert.Contains("{{WINMINT_MONITORS_JSON}}", template, StringComparison.Ordinal);
        Assert.Contains("{{WINMINT_DISPLAY_INDEX_PREFERENCES_JSON}}", template, StringComparison.Ordinal);
        Assert.Contains("\"winmint-m-1\" through \"winmint-m-4\"", template, StringComparison.Ordinal);
        Assert.Contains("layout \"BSP\"", template, StringComparison.Ordinal);
        Assert.DoesNotContain("serial", template, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"monitors\": [", template, StringComparison.Ordinal);
    }

    [Fact]
    public void Whkd_asset_contains_only_the_requested_alt_bindings()
    {
        string whkdrc = File.ReadAllText(Path.Combine(
            TestRepo.Root, "payload", "desktop", "komorebi", "whkdrc"));

        foreach (string key in new[] { "h", "j", "k", "l", "1", "2", "3", "4" })
        {
            Assert.Contains($"alt + {key}", whkdrc, StringComparison.Ordinal);
            Assert.Contains($"alt + shift + {key}", whkdrc, StringComparison.Ordinal);
        }

        Assert.Contains("toggle-pause", whkdrc, StringComparison.Ordinal);
        Assert.Contains("toggle-float", whkdrc, StringComparison.Ordinal);
        Assert.Contains("toggle-monocle", whkdrc, StringComparison.Ordinal);
        Assert.Contains("reload-configuration", whkdrc, StringComparison.Ordinal);
        Assert.Contains("komorebic close", whkdrc, StringComparison.Ordinal);
        Assert.DoesNotContain("win +", whkdrc, StringComparison.OrdinalIgnoreCase);
    }
}
