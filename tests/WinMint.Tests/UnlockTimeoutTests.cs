using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

public class UnlockTimeoutTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;
    private const string ExplorerShell = "explorer.exe";

    [Fact]
    public void Shell_wall_clock_timeout_unlocks()
    {
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        // Never-matching region forces settle to poll until wall-clock timeout.
        StickyRegion region = new(new RegionState("en-IE", 68, "GMT Standard Time", true));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    WallClockTimeout = TimeSpan.FromSeconds(4),
                    SettleDeadline = TimeSpan.FromMinutes(10),
                    SettlePollInterval = TimeSpan.FromSeconds(2),
                    FailedDwell = TimeSpan.FromSeconds(2),
                }),
            Env(time, winlogon, region, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.timeout", result.FinalStatus.Code);
        Assert.Equal(ExplorerShell, winlogon.Shell);
        Assert.Contains("Status:shell.timeout", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.StartsWith("Status:jobs.", StringComparison.Ordinal));
        Assert.Contains("shell.timeout", evidence.Documents[0].Phases);
        Assert.Equal("Failed", evidence.Documents[0].Outcome);
    }

    [Fact]
    public void Shell_stale_tenure_fails_open_and_unlocks()
    {
        ManualTimeProvider time = new();
        time.Advance(TimeSpan.FromMinutes(20));
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        StaleCheckpoints checkpoints = new(
            new TenureState(
                CheckpointInProgress: true,
                HeartbeatUtc: DateTimeOffset.UnixEpoch));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    StaleTenureThreshold = TimeSpan.FromMinutes(15),
                    FailedDwell = TimeSpan.Zero,
                }),
            Env(time, winlogon, new MatchingRegion(), splash, evidence, checkpoints),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.stale", result.FinalStatus.Code);
        Assert.Equal(ExplorerShell, winlogon.Shell);
        Assert.DoesNotContain(splash.Events, e => e == "Show");
        Assert.DoesNotContain(splash.Events, e => e.StartsWith("Status:settle.", StringComparison.Ordinal));
        Assert.Contains("shell.stale", evidence.Documents[0].Phases);
        Assert.Empty(checkpoints.HeartbeatsWritten);
    }

    [Fact]
    public void Shell_missing_heartbeat_with_checkpoint_fails_open()
    {
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        StaleCheckpoints checkpoints = new(
            new TenureState(CheckpointInProgress: true, HeartbeatUtc: null));

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: false, null, null, null, null),
                policy: SessionPolicy.SmokeDefaults with { FailedDwell = TimeSpan.Zero }),
            Env(time, winlogon, new MatchingRegion(), new RecordingSplashPresenter(), new RecordingEvidenceSink(), checkpoints),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.stale", result.FinalStatus.Code);
        Assert.Equal(ExplorerShell, winlogon.Shell);
    }

    [Fact]
    public void Shell_success_applies_appearance_once_then_unlocks()
    {
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    SettleDeadline = TimeSpan.Zero,
                    FailedDwell = TimeSpan.Zero,
                },
                appearance: new AppearanceOnce("Dark")),
            Env(time, winlogon, new MatchingRegion(), splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(ExplorerShell, winlogon.Shell);
        Assert.Equal(["explorer.exe"], winlogon.ShellWrites);
        int appearanceAt = splash.Events.IndexOf("Status:appearance.applied");
        Assert.True(appearanceAt >= 0, "appearance.applied status once");
        Assert.Equal(1, splash.Events.Count(e => e == "Status:appearance.applied"));
        Assert.Contains("Status:jobs.ok", splash.Events);
        int jobsOkAt = splash.Events.IndexOf("Status:jobs.ok");
        Assert.True(appearanceAt > jobsOkAt, "appearance after jobs");
        Assert.Contains("appearance.applied", evidence.Documents[0].Phases);
        Assert.Equal("Complete", evidence.Documents[0].Outcome);
    }

    private static ProvisioningBundle Bundle(
        DmaSettleTarget dma,
        SessionPolicy policy,
        AppearanceOnce? appearance = null) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: dma,
            Jobs: [new ProvisionJob("smoke.stub.ready", "stub")],
            Policy: policy,
            Supervisor: new SupervisorIdentity(SupervisorPath),
            Appearance: appearance);

    private static SessionEnvironment Env(
        TimeProvider time,
        IWinlogonRegistry winlogon,
        IRegionSnapshot region,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        ICheckpointStore? checkpoints = null) =>
        new(
            Time: time,
            Winlogon: winlogon,
            Region: region,
            Processes: new NoopProcesses(),
            Splash: splash,
            Checkpoints: checkpoints ?? new NoopCheckpoints(),
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
    }

    private sealed class StickyRegion(RegionState state) : IRegionSnapshot
    {
        public void Apply(DmaSettleTarget target) { }

        public RegionState Read() => state;
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

    private sealed class StaleCheckpoints(TenureState tenure) : ICheckpointStore
    {
        public List<DateTimeOffset> HeartbeatsWritten { get; } = [];

        public TenureState ReadTenure() => tenure;

        public void WriteHeartbeat(DateTimeOffset utcNow) => HeartbeatsWritten.Add(utcNow);
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

    private sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }
    }

    private sealed class NoopSecrets : ISecretScrubber
    {
        public void Wipe(ProvisioningBundle bundle) { }
    }

    /// <summary>Advances UTC on each timer due-time so Wait is instant under test.</summary>
    private sealed class ManualTimeProvider : TimeProvider
    {
        private DateTimeOffset _utcNow = DateTimeOffset.UnixEpoch;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan delta) => _utcNow += delta;

        public override ITimer CreateTimer(
            TimerCallback callback,
            object? state,
            TimeSpan dueTime,
            TimeSpan period) =>
            new AutoAdvanceTimer(this, callback, state, dueTime);

        private sealed class AutoAdvanceTimer : ITimer
        {
            private readonly ManualTimeProvider _owner;
            private readonly TimerCallback _callback;
            private readonly object? _state;
            private bool _disposed;

            public AutoAdvanceTimer(
                ManualTimeProvider owner,
                TimerCallback callback,
                object? state,
                TimeSpan dueTime)
            {
                _owner = owner;
                _callback = callback;
                _state = state;
                Change(dueTime, Timeout.InfiniteTimeSpan);
            }

            public bool Change(TimeSpan dueTime, TimeSpan period)
            {
                if (_disposed)
                {
                    return false;
                }

                if (dueTime == Timeout.InfiniteTimeSpan)
                {
                    return true;
                }

                if (dueTime < TimeSpan.Zero)
                {
                    dueTime = TimeSpan.Zero;
                }

                _owner.Advance(dueTime);
                _callback(_state);
                return true;
            }

            public void Dispose() => _disposed = true;

            public ValueTask DisposeAsync()
            {
                Dispose();
                return ValueTask.CompletedTask;
            }
        }
    }
}
