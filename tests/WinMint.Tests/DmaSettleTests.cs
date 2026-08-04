using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

public class DmaSettleTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Shell_final_hard_GeoId_mismatch_fails_and_skips_jobs()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-IE", 68, "GMT Standard Time", true)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        RecordingProcessHost processes = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, evidence, processes, winlogon),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("settle.hard_mismatch", result.FinalStatus.Code);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
        Assert.DoesNotContain(splash.Events, e => e.StartsWith("Status:jobs.", StringComparison.Ordinal));
        Assert.Empty(processes.Starts);
        Assert.Single(region.Applied);
        Assert.Equal(242, region.Applied[0].GeoId);
        Assert.Contains("settle.hard_mismatch", evidence.Documents[0].Phases);
        Assert.DoesNotContain("jobs.begin", evidence.Documents[0].Phases);
        Assert.DoesNotContain("jobs.ok", evidence.Documents[0].Phases);
    }

    [Fact]
    public void Shell_intermediate_probe_failures_are_non_authoritative()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ThrowRead("transient DMA probe"),
            new RegionRead.ThrowRead("still settling"),
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", true)));
        RecordingSplashPresenter splash = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: TightSettlePolicy()),
            Env(time, region, splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.hard_mismatch", StringComparison.Ordinal));
        Assert.DoesNotContain(splash.Events, e => e.Contains("settle.read_failed", StringComparison.Ordinal));
    }

    [Fact]
    public void Shell_soft_location_mismatch_warns_and_continues()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new(
            new RegionRead.ValueRead(new RegionState("en-GB", 242, "GMT Standard Time", false)));
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(
                dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
                policy: SessionPolicy.SmokeDefaults with
                {
                    SettleDeadline = TimeSpan.Zero,
                    SettlePollInterval = TimeSpan.Zero,
                }),
            Env(time, region, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:settle.location_warn", splash.Events);
        Assert.Contains("Status:jobs.ok", splash.Events);
        Assert.Contains("settle.location_warn", evidence.Documents[0].Phases);
        Assert.Equal("Complete", evidence.Documents[0].Outcome);
    }

    [Fact]
    public void Shell_dma_disabled_skips_settle_without_region_apply()
    {
        ManualTimeProvider time = new();
        ScriptedRegionSnapshot region = new();
        RecordingSplashPresenter splash = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(dma: new DmaSettleTarget(Enabled: false, null, null, null, null)),
            Env(time, region, splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Empty(region.Applied);
        Assert.Contains("Status:settle.skipped", splash.Events);
    }

    private static SessionPolicy TightSettlePolicy() =>
        SessionPolicy.SmokeDefaults with
        {
            SettleDeadline = TimeSpan.FromSeconds(4),
            SettlePollInterval = TimeSpan.FromSeconds(2),
        };

    private static ProvisioningBundle Bundle(DmaSettleTarget dma, SessionPolicy? policy = null) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: dma,
            Jobs: [new ProvisionJob("smoke.stub.ready", "stub")],
            Policy: policy ?? TightSettlePolicy(),
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(
        TimeProvider time,
        IRegionSnapshot region,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        IProcessHost? processes = null,
        IWinlogonRegistry? winlogon = null) =>
        new(
            Time: time,
            Winlogon: winlogon ?? new NoopWinlogon(),
            Region: region,
            Processes: processes ?? new RecordingProcessHost(),
            Splash: splash,
            Checkpoints: new NoopCheckpoints(),
            Secrets: new NoopSecrets(),
            Evidence: evidence);

    private sealed class RecordingWinlogon : IWinlogonRegistry
    {
        public string? Shell { get; set; }

        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => Shell;

        public void SetShell(string path) => Shell = path;

        public void GrantShellUnlockAccess(string username) { }
    }

    private abstract record RegionRead
    {
        public sealed record ValueRead(RegionState State) : RegionRead;

        public sealed record ThrowRead(string Message) : RegionRead;
    }

    private sealed class ScriptedRegionSnapshot : IRegionSnapshot
    {
        private readonly Queue<RegionRead> _reads;
        private RegionState? _lastGood;

        public ScriptedRegionSnapshot(params RegionRead[] reads) =>
            _reads = new Queue<RegionRead>(reads);

        public List<DmaSettleTarget> Applied { get; } = [];

        public void Apply(DmaSettleTarget target) => Applied.Add(target);

        public RegionState Read()
        {
            if (_reads.Count > 0)
            {
                return _reads.Dequeue() switch
                {
                    RegionRead.ValueRead v => _lastGood = v.State,
                    RegionRead.ThrowRead t => throw new InvalidOperationException(t.Message),
                    _ => throw new InvalidOperationException("Unknown scripted read."),
                };
            }

            // Sticky last probe — models OS state for the post-poll final snapshot Read.
            return _lastGood
                ?? throw new InvalidOperationException("No scripted region reads left.");
        }
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

    private sealed class NoopWinlogon : IWinlogonRegistry
    {
        public string? Shell { get; private set; } = SupervisorPath;

        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => Shell;

        public void SetShell(string path) => Shell = path;

        public void GrantShellUnlockAccess(string username) { }
    }

    private sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }

    private sealed class NoopSecrets : ISecretScrubber
    {
        public void Wipe(ProvisioningBundle bundle) { }
    }

    /// <summary>Advances UTC + monotonic stamp on timer due-time so settle Wait is instant under test.</summary>
    private sealed class ManualTimeProvider : TimeProvider
    {
        private DateTimeOffset _utcNow = DateTimeOffset.UnixEpoch;
        private long _timestamp;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public override long TimestampFrequency => TimeSpan.TicksPerSecond;

        public override long GetTimestamp() => _timestamp;

        public override ITimer CreateTimer(
            TimerCallback callback,
            object? state,
            TimeSpan dueTime,
            TimeSpan period) =>
            new AutoAdvanceTimer(this, callback, state, dueTime);

        private void Advance(TimeSpan delta)
        {
            _utcNow += delta;
            _timestamp += delta.Ticks;
        }

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
