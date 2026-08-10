using WinMint.Wizard;

namespace WinMint.Tests;

public class ApplyStatusReaderTests
{
    [Fact]
    public void TryRead_missing_file_returns_null()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-no-status-" + Guid.NewGuid().ToString("N") + ".txt");
        Assert.Null(ApplyStatusReader.TryRead(path, TestContext.Current.CancellationToken));
    }

    [Fact]
    public void TryRead_parses_stage_and_log()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-status-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "apply-status.txt");
        try
        {
            File.WriteAllText(
                path,
                """
                updated=2026-08-06T12:00:00.0000000Z
                stage=MountInstallWim
                log=C:\ProgramData\WinMint\work\logs\01-MountInstallWim.log
                """);

            ApplyStatusSnapshot? snap = ApplyStatusReader.TryRead(path, TestContext.Current.CancellationToken);
            Assert.NotNull(snap);
            Assert.Equal("MountInstallWim", snap.Stage);
            Assert.Equal(@"C:\ProgramData\WinMint\work\logs\01-MountInstallWim.log", snap.LogPath);
            Assert.Equal(
                "Building: MountInstallWim — C:\\ProgramData\\WinMint\\work\\logs\\01-MountInstallWim.log",
                ApplyStatusReader.FormatBusyLabel(snap));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void TryRead_latest_write_wins()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-status-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "apply-status.txt");
        try
        {
            File.WriteAllText(path, "updated=t1\nstage=idle\nlog=\n");
            Assert.Equal("idle", ApplyStatusReader.TryRead(path, TestContext.Current.CancellationToken)!.Stage);

            File.WriteAllText(path, "updated=t2\nstage=ExportWim\nlog=D:\\logs\\09-ExportWim.log\n");
            ApplyStatusSnapshot snap = ApplyStatusReader.TryRead(path, TestContext.Current.CancellationToken)!;
            Assert.Equal("ExportWim", snap.Stage);
            Assert.Equal(@"D:\logs\09-ExportWim.log", snap.LogPath);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void FormatBusyLabel_idle_done_and_empty_stay_null()
    {
        Assert.Null(ApplyStatusReader.FormatBusyLabel(new ApplyStatusSnapshot("idle", "")));
        Assert.Null(ApplyStatusReader.FormatBusyLabel(new ApplyStatusSnapshot("done", null)));
        Assert.Null(ApplyStatusReader.FormatBusyLabel(new ApplyStatusSnapshot("", null)));
        Assert.Equal(
            "Failed: ExportWim — x.log",
            ApplyStatusReader.FormatBusyLabel(new ApplyStatusSnapshot("failed:ExportWim", "x.log")));
    }

    [Fact]
    public void StatusPath_is_workdir_apply_status()
    {
        Assert.Equal(
            Path.Combine(@"C:\ProgramData\WinMint\work", "apply-status.txt"),
            ApplyStatusReader.StatusPath(@"C:\ProgramData\WinMint\work"));
    }
}
