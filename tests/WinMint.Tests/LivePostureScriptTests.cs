namespace WinMint.Tests;

public class LivePostureScriptTests
{
    [Fact]
    public void Registry_script_keeps_the_curated_names()
    {
        string script = File.ReadAllText(FindRepoFile("tools", "live", "Apply-Registry.ps1"));

        foreach (string name in new[]
        {
            "AllowNewsAndInterests",
            "DisableWindowsConsumerFeatures",
            "DisableFileSyncNGSC",
            "HideFirstRunExperience",
            "LongPathsEnabled",
            "DisableWpbtExecution",
            "AllowDevelopmentWithoutDevLicense",
            "AppsUseLightTheme",
            "HideFileExt",
            "TaskbarDa",
            "ShowCopilotButton",
            "SearchboxTaskbarMode",
            "EnabledState",
            "SubscribedContent-338389Enabled",
            "XDG_CONFIG_HOME",
        })
        {
            Assert.Contains(name, script, StringComparison.Ordinal);
        }

        Assert.DoesNotContain("ConsentPromptBehaviorAdmin", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Set-WinHomeLocation", script, StringComparison.Ordinal);
        Assert.Contains("OneDriveSetup.exe", script, StringComparison.Ordinal);
        Assert.Contains("/uninstall", script, StringComparison.Ordinal);
        Assert.Contains("Deprovisioned", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Copilot", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.XboxGamingOverlay", script, StringComparison.Ordinal);
    }

    private static string FindRepoFile(params string[] parts)
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "WinMint.slnx")))
        {
            dir = dir.Parent;
        }

        Assert.NotNull(dir);
        return Path.Combine([dir.FullName, .. parts]);
    }
}
