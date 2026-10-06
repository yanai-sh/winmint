using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ApplyOperatorMessagesTests
{
    [Fact]
    public void FormatFailed_includes_opcode_work_stage_log()
    {
        string text = ApplyOperatorMessages.FormatFailed(
            @"D:\work",
            "InjectDrivers",
            "DISM failed",
            "failed:InjectDrivers",
            @"D:\work\logs\09-InjectDrivers.log");

        Assert.Contains("InjectDrivers: DISM failed", text, StringComparison.Ordinal);
        Assert.Contains(@"work=D:\work", text, StringComparison.Ordinal);
        Assert.Contains("stage=failed:InjectDrivers", text, StringComparison.Ordinal);
        Assert.Contains(@"log=D:\work\logs\09-InjectDrivers.log", text, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatFailed_without_opcode_still_usable()
    {
        string text = ApplyOperatorMessages.FormatFailed(@"D:\work", null, "boom", null, null);
        Assert.True(text == "boom | work=D:\\work");
    }

    [Fact]
    public void FormatCrashed_names_workdir_and_status_hint()
    {
        string text = ApplyOperatorMessages.FormatCrashed(@"D:\work", 7);
        Assert.Contains("exited 7", text, StringComparison.Ordinal);
        Assert.Contains(@"work=D:\work", text, StringComparison.Ordinal);
        Assert.Contains("apply-status.txt", text, StringComparison.Ordinal);
    }
}
