using WinMint.Provisioning;
using WinMint.Contracts;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class CheckpointRebootTests
{
    [Fact]
    public async Task Shell_needsReboot_writes_checkpoint_and_keeps_Shell()
    {
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        RecordingCheckpoints checkpoints = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            BundleFastSettle(
            [
                new ProvisionJob("smoke.stub.reboot", ProvisionJobKind.Stub, NeedsReboot: true),
                new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub),
            ]),
            Env(winlogon, checkpoints, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, result.Outcome);
        Assert.Equal("jobs.reboot", result.FinalStatus.Code);
        Assert.Equal(SupervisorPath, winlogon.Shell);
        Assert.Empty(winlogon.ShellWrites);
        Assert.NotNull(checkpoints.LastWritten);
        Assert.Equal("jobs:1", checkpoints.LastWritten.Phase);
        Assert.Equal("Reboot", evidence.Documents[0].Outcome);
        Assert.Contains("jobs.reboot", evidence.Documents[0].Phases);
        Assert.DoesNotContain(splash.Events, e => e == "Status:appearance.applied");
        Assert.DoesNotContain(splash.Events, e => e == "Status:jobs.ok");
    }

    [Fact]
    public async Task Shell_resume_after_reboot_continues_jobs_then_unlocks()
    {
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        RecordingCheckpoints checkpoints = new();
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionEnvironment env = Env(winlogon, checkpoints, splash, evidence, processes);

        SessionResult first = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            BundleFastSettle(
            [
                new ProvisionJob("smoke.stub.reboot", ProvisionJobKind.Stub, NeedsReboot: true),
                new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub),
            ]),
            env,
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, first.Outcome);
        Assert.Equal("jobs:1", checkpoints.LastWritten!.Phase);
        Assert.Equal(SupervisorPath, winlogon.Shell);
        Assert.Single(processes.Starts);

        SessionResult second = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            BundleFastSettle(
            [
                new ProvisionJob("smoke.stub.reboot", ProvisionJobKind.Stub, NeedsReboot: true),
                new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub),
            ]),
            env,
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, second.Outcome);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
        Assert.Null(checkpoints.LastWritten);
        Assert.Equal(2, processes.Starts.Count);
        Assert.Contains("Status:checkpoint.resume", splash.Events);
        Assert.Contains("Status:settle.resume_skip", splash.Events);
        int resumeAt = splash.Events.IndexOf("Status:checkpoint.resume");
        int settleAt = splash.Events.FindLastIndex(e => e == "Status:settle.begin");
        Assert.True(settleAt >= 0 && settleAt < resumeAt, "settle runs before reboot only; resume skips settle");
        Assert.Contains("checkpoint.resume", evidence.Documents[^1].Phases);
        Assert.Contains("settle.resume_skip", evidence.Documents[^1].Phases);
        Assert.Equal("Complete", evidence.Documents[^1].Outcome);
    }

    [Fact]
    public void FileCheckpointStore_round_trips_phase_under_programdata()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-cp-" + Guid.NewGuid().ToString("N"));
        try
        {
            FileCheckpointStore store = new(root);
            store.WriteCheckpoint(new CheckpointState("jobs:2"));
            store.WriteHeartbeat(DateTimeOffset.UnixEpoch);

            Assert.Equal("jobs:2", store.TryReadCheckpoint()!.Phase);
            TenureState tenure = store.ReadTenure();
            Assert.True(tenure.CheckpointInProgress);
            Assert.Equal(DateTimeOffset.UnixEpoch, tenure.HeartbeatUtc);
            Assert.Equal("jobs:2", File.ReadAllText(Path.Combine(root, "checkpoint.json")).Trim());

            store.ClearCheckpoint();
            Assert.Null(store.TryReadCheckpoint());
            Assert.False(store.ReadTenure().CheckpointInProgress);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }
}
