using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

public class CheckpointRebootTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Shell_needsReboot_writes_checkpoint_and_keeps_Shell()
    {
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        RecordingCheckpoints checkpoints = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
            [
                new ProvisionJob("smoke.stub.reboot", "stub", NeedsReboot: true),
                new ProvisionJob("smoke.stub.complete", "stub"),
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
    public void Shell_resume_after_reboot_continues_jobs_then_unlocks()
    {
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        RecordingCheckpoints checkpoints = new();
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionEnvironment env = Env(winlogon, checkpoints, splash, evidence, processes);

        SessionResult first = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
            [
                new ProvisionJob("smoke.stub.reboot", "stub", NeedsReboot: true),
                new ProvisionJob("smoke.stub.complete", "stub"),
            ]),
            env,
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Reboot, first.Outcome);
        Assert.Equal("jobs:1", checkpoints.LastWritten!.Phase);
        Assert.Equal(SupervisorPath, winlogon.Shell);
        Assert.Single(processes.Starts);

        SessionResult second = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
            [
                new ProvisionJob("smoke.stub.reboot", "stub", NeedsReboot: true),
                new ProvisionJob("smoke.stub.complete", "stub"),
            ]),
            env,
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, second.Outcome);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
        Assert.Null(checkpoints.LastWritten);
        Assert.Equal(2, processes.Starts.Count);
        Assert.Contains("Status:checkpoint.resume", splash.Events);
        Assert.Contains("Status:settle.begin", splash.Events);
        int resumeAt = splash.Events.IndexOf("Status:checkpoint.resume");
        int settleAt = splash.Events.FindLastIndex(e => e == "Status:settle.begin");
        Assert.True(settleAt > resumeAt, "settle still runs after resume marker");
        Assert.Contains("checkpoint.resume", evidence.Documents[^1].Phases);
        Assert.Equal("Complete", evidence.Documents[^1].Outcome);
    }

    [Fact]
    public void FileCheckpointStore_round_trips_schema_under_programdata()
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
            string json = File.ReadAllText(Path.Combine(root, "checkpoint.json"));
            Assert.Contains(FileCheckpointStore.CheckpointSchemaVersion, json, StringComparison.Ordinal);

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

    private static ProvisioningBundle Bundle(IReadOnlyList<ProvisionJob> jobs) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults with
            {
                SettleDeadline = TimeSpan.Zero,
                FailedDwell = TimeSpan.Zero,
            },
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(
        IWinlogonRegistry winlogon,
        ICheckpointStore checkpoints,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        IProcessHost? processes = null) =>
        new(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: new MatchingRegion(),
            Processes: processes ?? new NoopProcesses(),
            Splash: splash,
            Checkpoints: checkpoints,
            Secrets: new NoopSecrets(),
            Evidence: evidence);

    private sealed class RecordingWinlogon : IWinlogonRegistry
    {
        public string? Shell { get; set; }

        public List<string> ShellWrites { get; } = [];

        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => Shell;

        public void SetShell(string path)
        {
            ShellWrites.Add(path);
            Shell = path;
        }
        public void GrantShellUnlockAccess(string username) { }
    }

    private sealed class RecordingCheckpoints : ICheckpointStore
    {
        public CheckpointState? LastWritten { get; private set; }

        public TenureState ReadTenure() =>
            new(LastWritten is not null, HeartbeatUtc: DateTimeOffset.UtcNow);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) => LastWritten = state;

        public CheckpointState? TryReadCheckpoint() => LastWritten;

        public void ClearCheckpoint() => LastWritten = null;
    }

    private sealed class MatchingRegion : IRegionSnapshot
    {
        private RegionState _state = new("en-GB", 242, "GMT Standard Time", true);

        public void Apply(DmaSettleTarget target) =>
            _state = new RegionState(
                target.Locale,
                target.GeoId,
                target.TimeZoneId,
                target.LocationServicesEnabled);

        public RegionState Read() => _state;
    }

    private sealed class RecordingSplashPresenter : ISplashPresenter
    {
        public List<string> Events { get; } = [];

        public void Show() => Events.Add("Show");

        public void SetStatus(SessionStatus status) => Events.Add($"Status:{status.Code}");
    }

    private sealed class RecordingEvidenceSink : IEvidenceSink
    {
        public List<ProvisioningEvidenceDocument> Documents { get; } = [];

        public EvidenceSnapshot Write(ProvisioningEvidenceDocument document)
        {
            Documents.Add(document);
            return new EvidenceSnapshot(document.SchemaVersion, $"memory:{Documents.Count}");
        }
    }

    private sealed class NoopProcesses : IProcessHost
    {
        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default) =>
            new(0);
    }

    private sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return new ProcessStartResult(0);
        }
    }

    private sealed class NoopSecrets : ISecretScrubber
    {
        public void Wipe(ProvisioningBundle bundle) { }
    }
}
