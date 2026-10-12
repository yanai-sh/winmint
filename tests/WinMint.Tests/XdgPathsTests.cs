using WinMint.Provisioning;

namespace WinMint.Tests;

public class XdgPathsTests
{
    [Fact]
    public void ConfigHome_uses_env_when_set_else_userprofile_config()
    {
        string? previous = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        try
        {
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", null);
            string fallback = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".config");
            Assert.Equal(fallback, XdgPaths.ConfigHome);

            string custom = Path.Combine(Path.GetTempPath(), "winmint-xdg-config-" + Guid.NewGuid().ToString("N"));
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", custom);
            Assert.Equal(custom, XdgPaths.ConfigHome);
            Assert.Equal(Path.Combine(custom, "yasb"), ShellDesktopLayout.DefaultYasbConfigDir);
            Assert.Equal(Path.Combine(custom, "whkdrc"), ShellDesktopLayout.DefaultWhkdrcPath);
        }
        finally
        {
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", previous);
        }
    }

    [Fact]
    public void DataHome_uses_env_when_set_else_local_share()
    {
        string? previous = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
        try
        {
            Environment.SetEnvironmentVariable("XDG_DATA_HOME", null);
            string fallback = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".local",
                "share");
            Assert.Equal(fallback, XdgPaths.DataHome);

            string custom = Path.Combine(Path.GetTempPath(), "winmint-xdg-data-" + Guid.NewGuid().ToString("N"));
            Environment.SetEnvironmentVariable("XDG_DATA_HOME", custom);
            Assert.Equal(custom, XdgPaths.DataHome);
        }
        finally
        {
            Environment.SetEnvironmentVariable("XDG_DATA_HOME", previous);
        }
    }

    [Fact]
    public void KomorebiConfigHome_prefers_tool_env_then_config_home()
    {
        string? previousKomorebi = Environment.GetEnvironmentVariable("KOMOREBI_CONFIG_HOME");
        string? previousConfig = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        try
        {
            Environment.SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", null);
            string configRoot = Path.Combine(Path.GetTempPath(), "winmint-xdg-cfg-" + Guid.NewGuid().ToString("N"));
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", configRoot);
            Assert.Equal(Path.Combine(configRoot, "komorebi"), XdgPaths.KomorebiConfigHome);
            Assert.Equal(Path.Combine(configRoot, "komorebi"), ShellDesktopLayout.DefaultKomorebiConfigDir);

            string custom = Path.Combine(Path.GetTempPath(), "winmint-komorebi-" + Guid.NewGuid().ToString("N"));
            Environment.SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", custom);
            Assert.Equal(custom, XdgPaths.KomorebiConfigHome);
            Assert.Equal(custom, ShellDesktopLayout.DefaultKomorebiConfigDir);
        }
        finally
        {
            Environment.SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", previousKomorebi);
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", previousConfig);
        }
    }

    [Fact]
    public void CacheHome_and_StateHome_fall_back_to_freedesktop_defaults()
    {
        string? previousCache = Environment.GetEnvironmentVariable("XDG_CACHE_HOME");
        string? previousState = Environment.GetEnvironmentVariable("XDG_STATE_HOME");
        try
        {
            Environment.SetEnvironmentVariable("XDG_CACHE_HOME", null);
            Environment.SetEnvironmentVariable("XDG_STATE_HOME", null);
            string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            Assert.Equal(Path.Combine(profile, ".cache"), XdgPaths.CacheHome);
            Assert.Equal(Path.Combine(profile, ".local", "state"), XdgPaths.StateHome);
        }
        finally
        {
            Environment.SetEnvironmentVariable("XDG_CACHE_HOME", previousCache);
            Environment.SetEnvironmentVariable("XDG_STATE_HOME", previousState);
        }
    }
}
