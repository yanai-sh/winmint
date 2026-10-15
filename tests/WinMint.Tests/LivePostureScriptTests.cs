using System.Text.RegularExpressions;

using WinMint.Orchestrator;

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
        Assert.DoesNotContain("Set-ReservedStorageState", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-WindowsCapability", script, StringComparison.Ordinal);
        Assert.Contains("OneDriveSetup.exe", script, StringComparison.Ordinal);
        Assert.Contains("/uninstall", script, StringComparison.Ordinal);
        Assert.Contains("takeown.exe", script, StringComparison.Ordinal);
        Assert.Contains("RunOnce", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.OneDrive", script, StringComparison.Ordinal);
        Assert.Contains("Deprovisioned", script, StringComparison.Ordinal);
        Assert.Contains("Clipchamp.Clipchamp_yxz26nhyzhsrt", script, StringComparison.Ordinal);
        Assert.Contains("left user folder", script, StringComparison.Ordinal);
    }

    [Fact]
    public void Registry_script_lists_the_product_inbox_strip()
    {
        string script = File.ReadAllText(FindRepoFile("tools", "live", "Apply-Registry.ps1"));
        HashSet<string> listed = QuotedBlock(script, "$inboxIds = @(");
        HashSet<string> expected = ProductPosture.AppxIds
            .Where(id => !ProductPosture.PreserveAppxSet.Contains(id))
            .ToHashSet(StringComparer.Ordinal);

        Assert.Equal(expected.OrderBy(id => id, StringComparer.Ordinal), listed.OrderBy(id => id, StringComparer.Ordinal));
        Assert.DoesNotContain("Microsoft.Windows.PeopleExperienceHost", listed);
        Assert.DoesNotContain("Windows.CBSPreview", listed);
        Assert.Contains("Microsoft.WindowsCalculator", listed);
        Assert.Contains("MicrosoftWindows.Client.WebExperience", listed);
    }

    private static HashSet<string> QuotedBlock(string script, string marker)
    {
        int start = script.IndexOf(marker, StringComparison.Ordinal);
        Assert.True(start >= 0, marker);
        start += marker.Length;
        int end = script.IndexOf(')', start);
        Assert.True(end > start);
        HashSet<string> set = new(StringComparer.Ordinal);
        foreach (Match match in Regex.Matches(script[start..end], "'([^']*)'"))
        {
            set.Add(match.Groups[1].Value);
        }

        return set;
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
