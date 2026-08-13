using WinMint.Orchestrator;
using WinMint.Wizard.ViewModels;

namespace WinMint.Tests;

public class ApplyProgressTests
{
    [Fact]
    public void TryReadProgress_missing_file_returns_null()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-no-status-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            Assert.Null(new ServicingWorkspace(root).TryReadProgress(TestContext.Current.CancellationToken));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void TryReadProgress_parses_stage_and_log()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-status-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            ServicingWorkspace workspace = new(root);
            File.WriteAllText(
                workspace.ApplyStatus,
                """
                updated=2026-08-06T12:00:00.0000000Z
                stage=MountInstallWim
                log=C:\ProgramData\WinMint\work\logs\01-MountInstallWim.log
                """);

            ApplyProgress? snap = workspace.TryReadProgress(TestContext.Current.CancellationToken);
            Assert.NotNull(snap);
            Assert.Equal("MountInstallWim", snap.Value.Stage);
            Assert.Equal(@"C:\ProgramData\WinMint\work\logs\01-MountInstallWim.log", snap.Value.LogPath);
            Assert.Equal(
                "Building: MountInstallWim — C:\\ProgramData\\WinMint\\work\\logs\\01-MountInstallWim.log",
                WizardViewModel.FormatBusyLabel(snap));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void TryReadProgress_latest_write_wins()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-status-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            ServicingWorkspace workspace = new(root);
            File.WriteAllText(workspace.ApplyStatus, "updated=t1\nstage=idle\nlog=\n");
            Assert.Equal("idle", workspace.TryReadProgress(TestContext.Current.CancellationToken)!.Value.Stage);

            File.WriteAllText(workspace.ApplyStatus, "updated=t2\nstage=ExportWim\nlog=D:\\logs\\09-ExportWim.log\n");
            ApplyProgress snap = workspace.TryReadProgress(TestContext.Current.CancellationToken)!.Value;
            Assert.Equal("ExportWim", snap.Stage);
            Assert.Equal(@"D:\logs\09-ExportWim.log", snap.LogPath);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void FormatBusyLabel_idle_done_and_empty_stay_null()
    {
        Assert.Null(WizardViewModel.FormatBusyLabel(new ApplyProgress("idle", "")));
        Assert.Null(WizardViewModel.FormatBusyLabel(new ApplyProgress("done", null)));
        Assert.Null(WizardViewModel.FormatBusyLabel(new ApplyProgress("", null)));
        Assert.Equal(
            "Failed: ExportWim — x.log",
            WizardViewModel.FormatBusyLabel(new ApplyProgress("failed:ExportWim", "x.log")));
    }

    [Fact]
    public void ApplyStatus_is_workdir_apply_status()
    {
        Assert.Equal(
            Path.Combine(@"C:\ProgramData\WinMint\work", "apply-status.txt"),
            new ServicingWorkspace(@"C:\ProgramData\WinMint\work").ApplyStatus);
    }
}
