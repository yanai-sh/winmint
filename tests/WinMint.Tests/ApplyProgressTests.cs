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
                log=C:\ProgramData\WinMint\work\apply-events.jsonl
                """);

            ApplyProgress? snap = workspace.TryReadProgress(TestContext.Current.CancellationToken);
            Assert.NotNull(snap);
            Assert.Equal("MountInstallWim", snap.Value.Stage);
            Assert.Equal(@"C:\ProgramData\WinMint\work\apply-events.jsonl", snap.Value.LogPath);
            Assert.Equal(
                "Building: MountInstallWim — C:\\ProgramData\\WinMint\\work\\apply-events.jsonl",
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

            File.WriteAllText(workspace.ApplyStatus, "updated=t2\nstage=ExportWim\nlog=D:\\work\\apply-events.jsonl\n");
            ApplyProgress snap = workspace.TryReadProgress(TestContext.Current.CancellationToken)!.Value;
            Assert.Equal("ExportWim", snap.Stage);
            Assert.Equal(@"D:\work\apply-events.jsonl", snap.LogPath);
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
    public void FormatApplyPresentation_includes_stage_and_event_rows()
    {
        string jsonl = Path.Combine(Path.GetTempPath(), "winmint-events-" + Guid.NewGuid().ToString("N") + ".jsonl");
        try
        {
            IEnumerable<string> lines = Enumerable.Range(1, 25).Select(i =>
                $$"""{"ts":"2026-08-06T12:00:00Z","kind":"opcode.end","opcode":"Stage{{i}}","outcome":"ok","summary":"done {{i}}"}""");
            File.WriteAllText(jsonl, string.Join('\n', lines));
            string? text = WizardViewModel.FormatApplyPresentation(
                new ApplyProgress("MountInstallWim", jsonl),
                readEventsTail: null,
                maxEvents: 20);
            Assert.NotNull(text);
            Assert.Contains("MountInstallWim", text, StringComparison.Ordinal);
            Assert.Contains("done 25", text, StringComparison.Ordinal);
            Assert.DoesNotContain("done 5", text, StringComparison.Ordinal);
        }
        finally
        {
            if (File.Exists(jsonl)) File.Delete(jsonl);
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
    public void FormatApplyPresentation_renders_formatted_event_rows()
    {
        ApplyEvent[] events =
        [
            new(Ts: "2026-08-06T12:00:00Z", Kind: "opcode.end", Opcode: "CatalogBits", Outcome: "ok", Summary: "Catalog BITS start KB5129195"),
            new(Ts: "2026-08-06T12:01:00Z", Kind: "opcode.end", Opcode: "AddQualityUpdates", Outcome: "ok", Summary: "AddQualityUpdates ok 12.3s"),
        ];
        string? text = WizardViewModel.FormatApplyPresentation(
            new ApplyProgress("AddQualityUpdates", "ignored.jsonl"),
            (_, _) => events);
        Assert.NotNull(text);
        Assert.Contains("CatalogBits", text, StringComparison.Ordinal);
        Assert.Contains("AddQualityUpdates", text, StringComparison.Ordinal);
        Assert.Contains("Catalog BITS start", text, StringComparison.Ordinal);
    }

    [Fact]
    public void ApplyBuildPresentation_parses_latest_proof_percent()
    {
        ApplyEvent[] events =
        [
            new(Kind: "proof", Opcode: "AddQualityUpdates", Percent: 25, Summary: "quality hash 25%"),
            new(Kind: "proof", Opcode: "AddQualityUpdates", Percent: 50, Summary: "quality hash 50%"),
        ];
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("AddQualityUpdates", "ignored.jsonl"),
            (_, _) => events);
        Assert.NotNull(presentation);
        Assert.Equal(50, presentation.Value.ProgressPercent);
        Assert.False(presentation.Value.IsProgressIndeterminate);
    }

    [Fact]
    public void ApplyBuildPresentation_busy_without_proof_stays_indeterminate()
    {
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("MountInstallWim", "ignored.jsonl"),
            (_, _) => [new(Kind: "run.start", Summary: "Apply start")]);
        Assert.NotNull(presentation);
        Assert.Null(presentation.Value.ProgressPercent);
        Assert.True(presentation.Value.IsProgressIndeterminate);
    }

    [Fact]
    public void ApplyBuildPresentation_parses_step_cue_from_opcode_end()
    {
        ApplyEvent[] events =
        [
            new(Kind: "opcode.end", Opcode: "MountInstallWim", Index: 10, Count: 14, Outcome: "ok", Summary: "mounted"),
            new(Kind: "opcode.end", Opcode: "AddQualityUpdates", Index: 11, Count: 14, Outcome: "ok", Summary: "updates"),
        ];
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("AddQualityUpdates", "ignored.jsonl"),
            (_, _) => events);
        Assert.NotNull(presentation);
        Assert.Equal("Step 11 of 14", presentation.Value.StepCue);
        Assert.True(presentation.Value.IsProgressIndeterminate);
        Assert.Null(presentation.Value.ProgressPercent);
    }

    [Fact]
    public void ApplyBuildPresentation_alive_line_is_working()
    {
        ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
            new ApplyProgress("MountInstallWim", "ignored.jsonl"),
            (_, _) => [new(Kind: "run.start", Summary: "Apply start")]);
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

    [Fact]
    public void ApplyBuildPresentation_reads_events_from_work_directory_when_log_empty()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-events-wd-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(
                ApplyEvents.PathFor(root),
                """{"ts":"2026-08-06T12:00:00Z","kind":"opcode.end","opcode":"ExportWim","outcome":"ok","summary":"exported"}""");
            ApplyBuildPresentation? presentation = ApplyBuildPresentationFormat.FromApplyProgress(
                new ApplyProgress("ExportWim", null),
                workDirectory: root);
            Assert.NotNull(presentation);
            Assert.Contains("ExportWim", presentation.Value.StatusTail, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
