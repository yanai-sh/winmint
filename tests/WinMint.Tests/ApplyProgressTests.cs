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

    [Fact]
    public void FormatApplyPresentation_includes_stage_and_log_tail()
    {
        string log = Path.Combine(Path.GetTempPath(), "winmint-tail-" + Guid.NewGuid().ToString("N") + ".log");
        try
        {
            File.WriteAllText(log, string.Join('\n', Enumerable.Range(1, 25).Select(i => $"line-{i}")));
            string? text = WizardViewModel.FormatApplyPresentation(
                new ApplyProgress("MountInstallWim", log),
                path => File.ReadAllLines(path),
                tailLines: 20);
            Assert.NotNull(text);
            Assert.Contains("MountInstallWim", text, StringComparison.Ordinal);
            Assert.Contains("line-25", text, StringComparison.Ordinal);
            Assert.DoesNotContain("line-5", text, StringComparison.Ordinal); // outside last 20
        }
        finally
        {
            if (File.Exists(log)) File.Delete(log);
        }
    }

    [Fact]
    public void FormatApplyPresentation_failed_stage_is_obvious()
    {
        string? text = WizardViewModel.FormatApplyPresentation(
            new ApplyProgress("failed:ExportWim", null));
        Assert.NotNull(text);
        Assert.StartsWith("Failed", text, StringComparison.Ordinal);
    }

    [Fact]
    public void FormatApplyPresentation_filters_heartbeat_and_dism_bar_lines()
    {
        string sampleBar = "[=====     50.0%                          ]";
        string[] lines =
        [
            "Catalog BITS start KB5129195",
            "AddQualityUpdates running 78s",
            sampleBar,
            "AddQualityUpdates ok 12.3s",
        ];
        string? text = WizardViewModel.FormatApplyPresentation(
            new ApplyProgress("AddQualityUpdates", "ignored.log"),
            _ => lines);
        Assert.NotNull(text);
        Assert.Contains("Catalog BITS start", text, StringComparison.Ordinal);
        Assert.Contains("AddQualityUpdates ok", text, StringComparison.Ordinal);
        Assert.DoesNotContain("running 78s", text, StringComparison.Ordinal);
        Assert.DoesNotContain(sampleBar, text, StringComparison.Ordinal);
    }

    [Fact]
    public void ApplyBuildPresentation_parses_latest_quality_hash_percent()
    {
        string[] lines =
        [
            "quality hash 25% 1024/4096 MB",
            "AddQualityUpdates running 40s",
            "quality hash 50% leaf.msu",
        ];
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("AddQualityUpdates", "ignored.log"),
            _ => lines);
        Assert.NotNull(presentation);
        Assert.Equal(50, presentation.Value.ProgressPercent);
        Assert.False(presentation.Value.IsProgressIndeterminate);
    }

    [Fact]
    public void ApplyBuildPresentation_busy_without_hash_stays_indeterminate()
    {
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("MountInstallWim", "ignored.log"),
            _ => ["MountInstallWim start"]);
        Assert.NotNull(presentation);
        Assert.Null(presentation.Value.ProgressPercent);
        Assert.True(presentation.Value.IsProgressIndeterminate);
    }

    [Fact]
    public void ApplyBuildPresentation_parses_apply_step_cue_without_progress_value()
    {
        string[] lines =
        [
            "Apply  10/14  MountInstallWim",
            "Apply  11/14  AddQualityUpdates",
        ];
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("AddQualityUpdates", "ignored.log"),
            _ => lines);
        Assert.NotNull(presentation);
        Assert.Equal("Step 11 of 14", presentation.Value.StepCue);
        Assert.True(presentation.Value.IsProgressIndeterminate);
        Assert.Null(presentation.Value.ProgressPercent);
    }

    [Fact]
    public void ApplyBuildPresentation_alive_line_from_latest_heartbeat()
    {
        string[] lines =
        [
            "MountInstallWim start",
            "MountInstallWim running 1103s",
        ];
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("MountInstallWim", "ignored.log"),
            _ => lines);
        Assert.NotNull(presentation);
        Assert.Equal("MountInstallWim · 18m 23s", presentation.Value.AliveLine);
    }

    [Fact]
    public void ApplyBuildPresentation_alive_line_without_heartbeat_is_working()
    {
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("MountInstallWim", "ignored.log"),
            _ => ["MountInstallWim start"]);
        Assert.NotNull(presentation);
        Assert.Equal("working…", presentation.Value.AliveLine);
    }

    [Fact]
    public void ApplyBuildPresentation_failed_reads_failure_and_transcript_hint()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-fail-ui-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(
                Path.Combine(root, ServicingWorkspace.FailureFileName),
                """{"schemaVersion":"1","opcode":"StampOfflinePolicies","message":"Cannot bind argument to parameter 'Line'"}""");
            File.WriteAllText(Path.Combine(root, "dism-transcript.log"), "=== stage ===\n");
            ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
                new ApplyProgress("failed:StampOfflinePolicies", null),
                workDirectory: root);
            Assert.NotNull(presentation);
            Assert.Equal("Failed: StampOfflinePolicies", presentation.Value.StageLine);
            Assert.Equal("Cannot bind argument to parameter 'Line'", presentation.Value.FailureDetail);
            Assert.Contains("dism-transcript.log", presentation.Value.TranscriptHint, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Theory]
    [InlineData(0, "0s")]
    [InlineData(59, "59s")]
    [InlineData(60, "1m")]
    [InlineData(1103, "18m 23s")]
    [InlineData(3600, "1h")]
    [InlineData(3661, "1h 1m")]
    public void FormatElapsed_human_grain(int seconds, string expected) =>
        Assert.Equal(expected, ApplyBuildPresentationFormat.FormatElapsed(seconds));

    [Theory]
    [InlineData("AddQualityUpdates running 78s", true)]
    [InlineData("Catalog BITS start KB1", false)]
    [InlineData("", false)]
    public void IsTrailHeartbeatLine_matches_host_grain(string line, bool expected) =>
        Assert.Equal(expected, ApplyBuildPresentationFormat.IsTrailHeartbeatLine(line));

    [Fact]
    public void IsDismProgressBarLine_rejects_quality_hash_milestone()
    {
        Assert.False(ApplyBuildPresentationFormat.IsDismProgressBarLine("quality hash 50% leaf.msu"));
        Assert.True(ApplyBuildPresentationFormat.IsDismProgressBarLine(
            "[=====     50.0%                          ]"));
        Assert.False(ApplyBuildPresentationFormat.IsDismProgressBarLine(""));
    }
}
