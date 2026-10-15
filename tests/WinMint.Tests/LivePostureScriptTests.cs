using System.Text.RegularExpressions;

using WinMint.Orchestrator;

namespace WinMint.Tests;

public class LivePostureScriptTests
{
    [Fact]
    public void Registry_script_keeps_the_curated_names()
    {
        string script = File.ReadAllText(FindRepoFile("post-install", "Apply-Registry.ps1"));

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
        Assert.DoesNotContain("OneDriveSetup.exe", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxPackage", script, StringComparison.Ordinal);
    }

    [Fact]
    public void OneDrive_script_purges_the_client_and_the_user_folder()
    {
        string script = File.ReadAllText(FindRepoFile("post-install", "Uninstall-OneDrive.ps1"));
        Assert.Contains("OneDriveSetup.exe", script, StringComparison.Ordinal);
        Assert.Contains("/uninstall", script, StringComparison.Ordinal);
        Assert.Contains("takeown.exe", script, StringComparison.Ordinal);
        Assert.Contains("RunOnce", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.OneDrive", script, StringComparison.Ordinal);
        Assert.Contains("OneDriveTemp", script, StringComparison.Ordinal);
        Assert.Contains("OneSyncSvc", script, StringComparison.Ordinal);
        Assert.Contains("SyncRootManager", script, StringComparison.Ordinal);
        Assert.Contains("Move-OneDriveChildren", script, StringComparison.Ordinal);
        Assert.Contains("PreventNetworkTrafficPreUserSignIn", script, StringComparison.Ordinal);
        Assert.DoesNotContain("left user folder", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxPackage", script, StringComparison.Ordinal);
    }

    [Fact]
    public void Registry_script_lists_the_product_inbox_strip()
    {
        string script = File.ReadAllText(FindRepoFile("post-install", "Remove-InboxApps.ps1"));
        Assert.Contains("Deprovisioned", script, StringComparison.Ordinal);
        Assert.Contains("Clipchamp.Clipchamp_yxz26nhyzhsrt", script, StringComparison.Ordinal);
        Assert.Contains("UseWindowsPowerShell", script, StringComparison.Ordinal);
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

    [Fact]
    public void Live_scripts_run_on_windows_powershell_and_powershell_7()
    {
        string live = FindRepoFile("post-install");
        string[] names =
        [
            "Apply-LivePosture.ps1",
            "Apply-Registry.ps1",
            "Uninstall-OneDrive.ps1",
            "Remove-InboxApps.ps1",
        ];
        foreach (string name in names)
        {
            string script = File.ReadAllText(Path.Combine(live, name));
            Assert.Contains("#requires -Version 5.1", script, StringComparison.Ordinal);
            Assert.DoesNotContain("#requires -Version 7", script, StringComparison.Ordinal);
            Assert.DoesNotContain("&&", script, StringComparison.Ordinal);
            Assert.DoesNotContain("??", script, StringComparison.Ordinal);
        }

        string orchestrator = File.ReadAllText(Path.Combine(live, "Apply-LivePosture.ps1"));
        int registry = orchestrator.IndexOf("Apply-Registry.ps1", StringComparison.Ordinal);
        int oneDrive = orchestrator.IndexOf("Uninstall-OneDrive.ps1", StringComparison.Ordinal);
        int inbox = orchestrator.IndexOf("Remove-InboxApps.ps1", StringComparison.Ordinal);
        Assert.True(registry >= 0 && registry < oneDrive && oneDrive < inbox);
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
