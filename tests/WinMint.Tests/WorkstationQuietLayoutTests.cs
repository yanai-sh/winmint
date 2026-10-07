using WinMint.Contracts;
using WinMint.Provisioning;

namespace WinMint.Tests;

public class WorkstationQuietLayoutTests
{
    [Fact]
    public void Quiet_table_includes_v1_taskbar_and_search_dwords()
    {
        IReadOnlyDictionary<string, int> advanced = QuietChromeFacts.ExplorerAdvancedDwords;
        Assert.Equal(0, advanced["ShowTaskViewButton"]);
        Assert.Equal(0, advanced["TaskbarDa"]);
        Assert.Equal(0, advanced["TaskbarMn"]);
        Assert.Equal(0, advanced["ShowCopilotButton"]);
        Assert.Equal(0, QuietChromeFacts.SearchboxTaskbarMode);
        Assert.Equal(1, QuietChromeFacts.HideRecycleBin);
        Assert.Equal(QuietChromeFacts.ExplorerAdvancedDwords, Win32WorkstationQuiet.ExplorerAdvancedDwords);
    }

    [Fact]
    public void Quiet_source_defers_taskbar_chrome_to_shell_chrome()
    {
        string quiet = File.ReadAllText(
            Path.Combine(TestRepo.Root, "src", "WinMint.Provisioning", "Win32WorkstationQuiet.cs"));
        Assert.Contains("ApplyTaskbarChrome", quiet, StringComparison.Ordinal);
        Assert.Contains("DisableDesktopSpotlight", quiet, StringComparison.Ordinal);
        Assert.Contains("LiveOnlyTaskbarExplorerAdvanced", quiet, StringComparison.Ordinal);
        // ApplyUserRegistry must not write Searchbox — only ApplyTaskbarChrome (shell.chrome) does.
        int userReg = quiet.IndexOf("private static void ApplyUserRegistry", StringComparison.Ordinal);
        int taskbar = quiet.IndexOf("public static void ApplyTaskbarChrome", StringComparison.Ordinal);
        Assert.True(userReg >= 0 && taskbar > userReg);
        Assert.DoesNotContain(
            "SearchboxTaskbarMode",
            quiet.AsSpan(userReg, taskbar - userReg),
            StringComparison.Ordinal);
    }
}
