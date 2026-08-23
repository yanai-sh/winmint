using WinMint.Provisioning;

namespace WinMint.Tests;

public class WorkstationQuietLayoutTests
{
    [Fact]
    public void Quiet_table_includes_v1_taskbar_and_search_dwords()
    {
        IReadOnlyDictionary<string, int> advanced = Win32WorkstationQuiet.ExplorerAdvancedDwords;
        Assert.Equal(0, advanced["ShowTaskViewButton"]);
        Assert.Equal(0, advanced["TaskbarDa"]);
        Assert.Equal(0, advanced["TaskbarMn"]);
        Assert.Equal(0, advanced["ShowCopilotButton"]);
        Assert.Equal(0, Win32WorkstationQuiet.SearchboxTaskbarMode);
        Assert.Equal(1, Win32WorkstationQuiet.HideRecycleBin);
    }
}
