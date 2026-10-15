namespace WinMint.Tests;

public class LivePostureScriptTests
{
    [Fact]
    public void Live_scripts_keep_the_curated_registry_names()
    {
        string machine = File.ReadAllText(FindRepoFile("tools", "live", "Apply-Machine.ps1"));
        string user = File.ReadAllText(FindRepoFile("tools", "live", "Apply-User.ps1"));

        foreach (string name in new[]
        {
            "AllowNewsAndInterests",
            "DisableWindowsConsumerFeatures",
            "DisableFileSyncNGSC",
            "HideFirstRunExperience",
            "LongPathsEnabled",
            "DisableWpbtExecution",
            "AllowDevelopmentWithoutDevLicense",
        })
        {
            Assert.Contains(name, machine, StringComparison.Ordinal);
        }

        Assert.DoesNotContain("ConsentPromptBehaviorAdmin", machine, StringComparison.Ordinal);

        foreach (string name in new[]
        {
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
            Assert.Contains(name, user, StringComparison.Ordinal);
        }
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
