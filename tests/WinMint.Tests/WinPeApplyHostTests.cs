using WinMint.WinPeApply;

namespace WinMint.Tests;

public class WinPeApplyHostTests
{
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

    [Fact]
    public void Run_captures_LaunchApply_stdout_on_success()
    {
        string dir = Directory.CreateTempSubdirectory("winmint-winpe-apply-run").FullName;
        try
        {
            StageCmdAndLaunch(dir, "@echo off\r\necho hello-from-launch\r\nexit /b 0\r\n");

            int code = WinPeApplyHost.Run(dir, holdFailureConsole: false);

            Assert.Equal(0, code);
            Assert.Contains("hello-from-launch", ReadApplyLog(), StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Run_captures_LaunchApply_stdout_on_failure()
    {
        string dir = Directory.CreateTempSubdirectory("winmint-winpe-apply-fail").FullName;
        try
        {
            StageCmdAndLaunch(dir, "@echo off\r\necho fail-from-launch\r\nexit /b 1\r\n");

            int code = WinPeApplyHost.Run(dir, holdFailureConsole: false);

            Assert.Equal(1, code);
            Assert.Contains("fail-from-launch", ReadApplyLog(), StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    private static void StageCmdAndLaunch(string system32, string launchBody)
    {
        string log = Path.Combine(Path.GetTempPath(), "winmint-apply.log");
        if (File.Exists(log))
        {
            File.Delete(log);
        }

        File.Copy(
            Path.Combine(Environment.SystemDirectory, "cmd.exe"),
            Path.Combine(system32, "cmd.exe"));
        File.WriteAllText(Path.Combine(system32, WinPeApplyHost.LaunchName), launchBody);
    }

    private static string ReadApplyLog()
    {
        string log = Path.Combine(Path.GetTempPath(), "winmint-apply.log");
        Assert.True(File.Exists(log), "LaunchApply stdout should land in winmint-apply.log");
        return File.ReadAllText(log);
    }
}
