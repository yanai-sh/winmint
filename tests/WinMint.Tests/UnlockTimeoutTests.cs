using WinMint.Contracts;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

using DmaSettleTarget = WinMint.Contracts.DmaSettleTarget;

namespace WinMint.Tests;

public class UnlockTimeoutTests
{
    private const string ExplorerShell = "explorer.exe";

    [Fact]
    public async Task Shell_wall_clock_timeout_unlocks()
    {
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        // Never-matching region forces settle to poll until tenure timeout.
        StickyRegion region = new(new RegionState("en-IE", 68, "GMT Standard Time", true));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
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
    public async Task Shell_wall_clock_jump_during_settle_does_not_false_timeout()
    {
        // Hyper-V IC/NTP can jump guest UTC ~+3h mid-settle; tenure deadlines must be monotonic.
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        JumpThenMatchRegion region = new(
            mismatch: new RegionState("en-IE", 68, "GMT Standard Time", true),
            match: new RegionState("en-GB", 242, "GMT Standard Time", true),
            onFirstMismatch: () => time.JumpWallClock(TimeSpan.FromHours(3)));
        RecordingSplashPresenter splash = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    WallClockTimeout = TimeSpan.FromSeconds(10),
                    SettleDeadline = TimeSpan.FromSeconds(10),
                    SettlePollInterval = TimeSpan.FromSeconds(1),
                    FailedDwell = TimeSpan.Zero,
                }),
            Env(time, winlogon, region, splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.Contains("shell.timeout", StringComparison.Ordinal));
        Assert.Equal(ExplorerShell, winlogon.Shell);
    }

    [Fact]
    public async Task Shell_stale_tenure_fails_open_and_unlocks()
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

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
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
    public async Task Shell_missing_heartbeat_with_checkpoint_fails_open()
    {
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        StaleCheckpoints checkpoints = new(
            new TenureState(CheckpointInProgress: true, HeartbeatUtc: null));

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget(null, null, null, null),
                policy: SessionPolicy.SmokeDefaults with { FailedDwell = TimeSpan.Zero },
                dmaEnabled: false),
            Env(time, winlogon, new MatchingRegion(), new RecordingSplashPresenter(), new RecordingEvidenceSink(), checkpoints),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.stale", result.FinalStatus.Code);
        Assert.Equal(ExplorerShell, winlogon.Shell);
    }

    [Fact]
    public async Task Shell_success_unlocks_after_jobs()
    {
        ManualTimeProvider time = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(
                dma: new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    SettleDeadline = TimeSpan.Zero,
                    FailedDwell = TimeSpan.Zero,
                }),
            Env(time, winlogon, new MatchingRegion(), splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(ExplorerShell, winlogon.Shell);
        Assert.Equal(["explorer.exe"], winlogon.ShellWrites);
        Assert.Contains("Status:jobs.ok", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.StartsWith("Status:appearance.", StringComparison.Ordinal));
        Assert.Equal("Complete", evidence.Documents[0].Outcome);
    }

    private static ProvisioningBundle Bundle(
        DmaSettleTarget dma,
        SessionPolicy policy,
        bool dmaEnabled = true) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: dma,
            Jobs: [new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub)],
            Policy: policy,
            SupervisorShellPath: SupervisorPath,
            DmaEnabled: dmaEnabled);

    private static ShellEnvironment Env(
        TimeProvider time,
        IWinlogonRegistry winlogon,
        IRegionSnapshot region,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        ICheckpointStore? checkpoints = null) =>
        ProvisioningSessionTestFakes.Env(
            new FakeGuestMachine
            {
                Winlogon = winlogon,
                Region = region,
                Checkpoints = checkpoints ?? new NoopCheckpoints(),
            },
            evidence,
            time,
            splash);

    private sealed class StickyRegion(RegionState state) : IRegionSnapshot
    {
        public void Apply(DmaSettleTarget target) { }

        public RegionState Read() => state;
    }

    /// <summary>First probe mismatches (and may jump wall clock); later probes match.</summary>
    private sealed class JumpThenMatchRegion(RegionState mismatch, RegionState match, Action onFirstMismatch) : IRegionSnapshot
    {
        private readonly RegionState _mismatch = mismatch;
        private readonly RegionState _match = match;
        private readonly Action _onFirstMismatch = onFirstMismatch;
        private int _reads;

        public void Apply(DmaSettleTarget target) { }

        public RegionState Read()
        {
            if (_reads++ == 0)
            {
                _onFirstMismatch();
                return _mismatch;
            }

            return _match;
        }
    }

    private sealed class StaleCheckpoints(TenureState tenure) : ICheckpointStore
    {
        public List<DateTimeOffset> HeartbeatsWritten { get; } = [];

        public TenureState ReadTenure() => tenure;

        public void WriteHeartbeat(DateTimeOffset utcNow) => HeartbeatsWritten.Add(utcNow);

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }
}
