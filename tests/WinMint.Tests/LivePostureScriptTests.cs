using System.Text;
using System.Text.RegularExpressions;

using WinMint.Orchestrator;

namespace WinMint.Tests;

public class LivePostureScriptTests
{
    [Fact]
    public void Registry_tasks_keep_the_curated_names()
    {
        string live = FindRepoFile("post-install");
        string orchestrator = File.ReadAllText(Path.Combine(live, "Apply-Registry.ps1"));
        string[] tasks =
        [
            "Disable-ConsumerFeatures.ps1",
            "Set-QuietTaskbar.ps1",
            "Disable-EdgePromotions.ps1",
            "Set-ExplorerView.ps1",
            "Set-SystemPolicy.ps1",
        ];

        int last = -1;
        var script = new StringBuilder();
        foreach (string task in tasks)
        {
            int at = orchestrator.IndexOf(task, StringComparison.Ordinal);
            Assert.True(at > last, task);
            last = at;
            string path = Path.Combine(live, "registry", task);
            string body = File.ReadAllText(path);
            Assert.Contains("Registry.ps1", body, StringComparison.Ordinal);
            script.AppendLine(body);
        }

        Assert.DoesNotContain("'Registry.ps1'", orchestrator, StringComparison.Ordinal);
        string combined = script.ToString();
        foreach (string name in new[]
        {
            "AllowNewsAndInterests",
            "DisableWindowsConsumerFeatures",
            "EnableActivityFeed",
            "PublishUserActivities",
            "UploadUserActivities",
            "DODownloadMode",
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
            "PreventDeviceMetadataFromNetwork",
            "NewTabPageLocation",
            "AutoDownload",
        })
        {
            Assert.Contains(name, combined, StringComparison.Ordinal);
        }

        Assert.Contains("'EnableActivityFeed' 0", combined, StringComparison.Ordinal);
        Assert.Contains("'DODownloadMode' 0", combined, StringComparison.Ordinal);
        Assert.Contains("'Enabled' 3", File.ReadAllText(Path.Combine(live, "registry", "Set-SystemPolicy.ps1")), StringComparison.Ordinal);
        Assert.DoesNotContain("GlobalUserDisabled", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("SvcHostSplitThresholdInKB", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("Set-Service", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("ConsentPromptBehaviorAdmin", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("Set-WinHomeLocation", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("Set-ReservedStorageState", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-WindowsCapability", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("OneDriveSetup.exe", combined, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxPackage", combined, StringComparison.Ordinal);
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
        Assert.Contains("DisableFileSyncNGSC", script, StringComparison.Ordinal);
        Assert.Contains("%USERPROFILE%\\Desktop", script, StringComparison.Ordinal);
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
        Assert.Contains("dism.exe /Online /Get-ProvisionedAppxPackages /English", script, StringComparison.Ordinal);
        Assert.Contains("/Remove-ProvisionedAppxPackage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Get-AppxProvisionedPackage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Remove-AppxProvisionedPackage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Generic.List", script, StringComparison.Ordinal);
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
        foreach (string path in Directory.GetFiles(live, "*.ps1", SearchOption.AllDirectories))
        {
            string script = File.ReadAllText(path);
            Assert.Contains("#requires -Version 5.1", script, StringComparison.Ordinal);
            Assert.DoesNotContain("#requires -Version 7", script, StringComparison.Ordinal);
            Assert.DoesNotContain("&&", script, StringComparison.Ordinal);
            Assert.DoesNotContain("??", script, StringComparison.Ordinal);
            if (Path.GetFileName(path).Equals("Registry.ps1", StringComparison.Ordinal))
            {
                Assert.Contains("function Set-RegDword", script, StringComparison.Ordinal);
                Assert.DoesNotContain("[switch] $DryRun", script, StringComparison.Ordinal);
                continue;
            }

            Assert.Contains("[switch] $DryRun", script, StringComparison.Ordinal);
        }

        string orchestrator = File.ReadAllText(Path.Combine(live, "Apply-LivePosture.ps1"));
        int registry = orchestrator.IndexOf("Apply-Registry.ps1", StringComparison.Ordinal);
        int oneDrive = orchestrator.IndexOf("Uninstall-OneDrive.ps1", StringComparison.Ordinal);
        int inbox = orchestrator.IndexOf("Remove-InboxApps.ps1", StringComparison.Ordinal);
        int drivers = orchestrator.LastIndexOf("Install-SurfaceDrivers.ps1", StringComparison.Ordinal);
        Assert.True(registry >= 0 && registry < oneDrive && oneDrive < inbox && inbox < drivers);
        Assert.Contains("[switch] $Drivers", orchestrator, StringComparison.Ordinal);
        string driverScript = File.ReadAllText(Path.Combine(live, "Install-SurfaceDrivers.ps1"));
        Assert.Contains("surface-laptop-7", driverScript, StringComparison.Ordinal);
        Assert.Contains("msiexec.exe", driverScript, StringComparison.Ordinal);
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
