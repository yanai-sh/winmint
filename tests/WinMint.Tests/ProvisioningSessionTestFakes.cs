using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

/// <summary>Shared S3 fakes for ProvisioningSession metal / shell tenure tests.</summary>
internal static class ProvisioningSessionTestFakes
{
    internal static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    internal static ProvisioningBundle Bundle(IReadOnlyList<ProvisionJob> jobs) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath));

    internal static ProvisioningBundle Bundle(
        IReadOnlyList<ProvisionJob> jobs,
        IReadOnlyList<string> removeProvisionedAppx) =>
        Bundle(jobs) with { RemoveProvisionedAppx = removeProvisionedAppx };

    internal static ProvisioningBundle BundleFastSettle(IReadOnlyList<ProvisionJob> jobs) =>
        Bundle(jobs) with
        {
            Policy = SessionPolicy.SmokeDefaults with
            {
                SettleDeadline = TimeSpan.Zero,
                FailedDwell = TimeSpan.Zero,
            },
        };

    internal static SessionEnvironment Env(
        IProcessHost processes,
        IEvidenceSink evidence,
        ICheckpointStore? checkpoints = null,
        ISystemReboot? reboot = null,
        IAppxPackageManager? appx = null,
        ISplashPresenter? splash = null,
        Func<string?>? resolveScoopCmd = null) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: processes,
            Splash: splash ?? new RecordingSplashPresenter(),
            Checkpoints: checkpoints ?? new NoopCheckpoints(),
            Evidence: evidence,
            Reboot: reboot,
            Appx: appx,
            ResolveScoopCmd: resolveScoopCmd);

    internal static SessionEnvironment Env(
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
            Evidence: evidence);

    internal static SessionEnvironment Env(IAppxPackageManager appx, ISplashPresenter splash) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: new NoopProcesses(),
            Splash: splash,
            Checkpoints: new NoopCheckpoints(),
            Evidence: new NoopEvidence(),
            Appx: appx);

    internal sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public int ExitCode { get; set; }

        public Func<string, IReadOnlyList<string>, ProcessStartResult>? OnRun { get; init; }

        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return OnRun?.Invoke(fileName, arguments) ?? new ProcessStartResult(ExitCode);
        }
    }

    internal sealed class RecordingSplashPresenter : ISplashPresenter
    {
        public List<string> Events { get; } = [];

        public void Show() => Events.Add("Show");

        public void SetStatus(SessionStatus status) => Events.Add($"Status:{status.Code}");
    }

    internal sealed class RecordingEvidenceSink : IEvidenceSink
    {
        public List<ProvisioningEvidenceDocument> Documents { get; } = [];

        public EvidenceSnapshot Write(ProvisioningEvidenceDocument document)
        {
            Documents.Add(document);
            return new EvidenceSnapshot(document.SchemaVersion, $"memory:{Documents.Count}");
        }
    }

    internal sealed class RecordingAppx : IAppxPackageManager
    {
        public List<AppxPackageInfo> Registered { get; } = [];
        public List<AppxPackageInfo> Provisioned { get; } = [];
        public List<string> RemovedFullNames { get; } = [];
        public List<string> DeprovisionedFamilyNames { get; } = [];
        public List<string> RegisteredFamilyNames { get; } = [];

        public string? WingetPath { get; init; }

        public int EnsureSystemFullControlCalls { get; private set; }

        public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId) =>
            Registered.Where(p => WinRTAppxPackageManager.MatchesCatalogId(p, catalogId)).ToArray();

        public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId) =>
            Provisioned.Where(p => WinRTAppxPackageManager.MatchesCatalogId(p, catalogId)).ToArray();

        public void RemovePackage(string packageFullName) => RemovedFullNames.Add(packageFullName);

        public void DeprovisionPackageFamily(string packageFamilyName) =>
            DeprovisionedFamilyNames.Add(packageFamilyName);

        public void RegisterPackageFamilyForCurrentUser(string packageFamilyName) =>
            RegisteredFamilyNames.Add(packageFamilyName);

        public void EnsureSystemFullControlOnWingetFrameworkPackages() => EnsureSystemFullControlCalls++;

        public string? TryResolveWingetExecutablePath() => WingetPath;
    }

    internal sealed class RecordingSystemReboot : ISystemReboot
    {
        public bool Requested { get; private set; }

        public void RequestReboot() => Requested = true;
    }

    internal sealed class RecordingCheckpoints : ICheckpointStore
    {
        public CheckpointState? LastWritten { get; private set; }

        public TenureState ReadTenure() =>
            new(CheckpointInProgress: LastWritten is not null, HeartbeatUtc: DateTimeOffset.UtcNow);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) => LastWritten = state;

        public CheckpointState? TryReadCheckpoint() => LastWritten;

        public void ClearCheckpoint() => LastWritten = null;
    }

    internal sealed class RecordingWinlogon : IWinlogonRegistry
    {
        public string? Shell { get; set; } = SupervisorPath;

        public List<string> ShellWrites { get; } = [];

        public void SetAutoLogon(string username, string password) { }

        public void ClearAutoLogon() { }

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

    internal sealed class MatchingRegion : IRegionSnapshot
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

    internal sealed class NoopWinlogon : IWinlogonRegistry
    {
        public string? Shell { get; private set; } = SupervisorPath;

        public void SetAutoLogon(string username, string password) { }

        public void ClearAutoLogon() { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => Shell;

        public void SetShell(string path) => Shell = path;

        public void GrantShellUnlockAccess(string username) { }
    }

    internal sealed class NoopProcesses : IProcessHost
    {
        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default) =>
            new(0);
    }

    internal sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }

    internal sealed class NoopSplash : ISplashPresenter
    {
        public void Show() { }

        public void SetStatus(SessionStatus status) { }
    }

    internal sealed class NoopRegion : IRegionSnapshot
    {
        public void Apply(DmaSettleTarget target) { }

        public RegionState Read() => new(null, null, null, null);
    }

    internal sealed class NoopEvidence : IEvidenceSink
    {
        public EvidenceSnapshot Write(ProvisioningEvidenceDocument document) =>
            new(document.SchemaVersion, "memory:1");
    }

    internal sealed class RecordingLocalAccounts : ILocalAccounts
    {
        public List<string> Deleted { get; } = [];

        public void TryDeleteLocalUserAndProfile(string username) => Deleted.Add(username);
    }

    internal sealed class ThrowingLocalAccounts : ILocalAccounts
    {
        public void TryDeleteLocalUserAndProfile(string username) =>
            throw new InvalidOperationException("simulated delete failure");
    }

    /// <summary>Winlogon fake with autologon capture for MachineSetup tests.</summary>
    internal sealed class FakeWinlogonRegistry : IWinlogonRegistry
    {
        public string? DefaultUserName { get; private set; }
        public string? DefaultPassword { get; private set; }
        public bool AutoAdminLogon { get; private set; }
        public string? Shell { get; set; }
        public bool ShellWriteNoOp { get; set; }

        public void SetAutoLogon(string username, string password)
        {
            DefaultUserName = username;
            DefaultPassword = password;
            AutoAdminLogon = true;
        }

        public void ClearAutoLogon()
        {
            AutoAdminLogon = false;
            DefaultPassword = null;
            DefaultUserName = null;
        }

        public string? GetDefaultUserName() => DefaultUserName;

        public bool GetAutoAdminLogon() => AutoAdminLogon;

        public string? GetShell() => Shell;

        public void SetShell(string path)
        {
            if (!ShellWriteNoOp)
            {
                Shell = path;
            }
        }

        public void GrantShellUnlockAccess(string username) { }
    }

    internal sealed class RecordingWipeSecrets
    {
        public int WipeCount { get; private set; }

        public ProvisioningBundle? LastBundle { get; private set; }

        public void Wipe(ProvisioningBundle bundle)
        {
            WipeCount++;
            LastBundle = bundle;
        }
    }

    /// <summary>Advances UTC + monotonic stamp on timer due-time; wall jump is UTC-only.</summary>
    internal sealed class ManualTimeProvider : TimeProvider
    {
        private DateTimeOffset _utcNow = DateTimeOffset.UnixEpoch;
        private long _timestamp;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public override long TimestampFrequency => TimeSpan.TicksPerSecond;

        public override long GetTimestamp() => _timestamp;

        public void Advance(TimeSpan delta)
        {
            _utcNow += delta;
            _timestamp += delta.Ticks;
        }

        /// <summary>Guest NTP/IC-style UTC jump — must not advance tenure deadlines.</summary>
        public void JumpWallClock(TimeSpan delta) => _utcNow += delta;

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
