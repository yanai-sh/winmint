using System.Diagnostics;
using WinMint.WinPeApply;

namespace WinMint.Tests;

public class WinPeApplyHostTests
{
    [Fact]
    public void Hidden_launch_creates_no_window_and_skips_quickedit_respawn()
    {
        ProcessStartInfo psi = WinPeApplyHost.HiddenLaunch(
            @"X:\Windows\System32",
            @"X:\Windows\Temp\winmint-apply.log");

        Assert.True(psi.CreateNoWindow);
        Assert.False(psi.UseShellExecute);
        Assert.Equal("1", psi.Environment[WinPeApplyHost.QuickEditSkip]);
        Assert.Contains(WinPeApplyHost.LaunchName, psi.ArgumentList[1], StringComparison.Ordinal);
    }

    [Fact]
    public void Missing_launcher_fails_without_opening_a_console()
    {
        string dir = Directory.CreateTempSubdirectory("winmint-winpe-apply").FullName;
        try
        {
            int code = WinPeApplyHost.Run(dir, holdFailureConsole: false);
            Assert.Equal(1, code);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
