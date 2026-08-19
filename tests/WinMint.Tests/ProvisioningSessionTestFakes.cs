using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

namespace WinMint.Tests;

/// <summary>Shared S3 fakes for ProvisioningSession machine setup / shell tenure tests.</summary>
internal static class ProvisioningSessionTestFakes
{
    internal static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    internal static ProvisioningBundle Bundle(IReadOnlyList<ProvisionJob> jobs) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults,
            SupervisorShellPath: SupervisorPath);

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

    internal static ShellEnvironment Env(
        FakeGuestMachine guest,
        IEvidenceSink evidence,
        TimeProvider? time = null,
        ISplashPresenter? splash = null) =>
        new(
            Time: time ?? TimeProvider.System,
            Guest: guest,
            Splash: splash ?? new RecordingSplashPresenter(),
            Evidence: evidence);

    internal static ShellEnvironment Env(
        IProcessHost processes,
        IEvidenceSink evidence,
        ICheckpointStore? checkpoints = null,
        ISystemReboot? reboot = null,
        IAppxPackageManager? appx = null,
        ISplashPresenter? splash = null,
        Func<string?>? resolveScoopCmd = null,
        Func<bool>? isWslPlatformReady = null,
        Action? applyWorkstationQuiet = null,
        Action? suppressWslOobe = null,
        IAssetDownload? assetDownload = null,
        IDmaSetupRegion? dmaSetup = null) =>
        Env(
            new FakeGuestMachine
            {
                Processes = processes,
                Checkpoints = checkpoints ?? new NoopCheckpoints(),
                Appx = appx,
                Reboot = reboot,
                ResolveScoopCmd = resolveScoopCmd,
                IsWslPlatformReadyCallback = isWslPlatformReady ?? (() => false),
                ApplyWorkstationQuietCallback = applyWorkstationQuiet ?? (() => { }),
                SuppressWslOobeCallback = suppressWslOobe ?? (() => { }),
                AssetDownload = assetDownload,
                DmaSetup = dmaSetup ?? new OkDmaSetupRegion(),
            },
            evidence,
            splash: splash);

    internal static ShellEnvironment Env(
        IWinlogonRegistry winlogon,
        ICheckpointStore checkpoints,
        ISplashPresenter splash,
        IEvidenceSink evidence,
        IProcessHost? processes = null,
        IDmaSetupRegion? dmaSetup = null) =>
        Env(
            new FakeGuestMachine
            {
                Winlogon = winlogon,
                Processes = processes ?? new NoopProcesses(),
                Checkpoints = checkpoints,
                DmaSetup = dmaSetup ?? new OkDmaSetupRegion(),
            },
            evidence,
            splash: splash);

    internal static ShellEnvironment Env(
        IAppxPackageManager appx,
        ISplashPresenter splash,
        IDmaSetupRegion? dmaSetup = null) =>
        Env(
            new FakeGuestMachine
            {
                Appx = appx,
                DmaSetup = dmaSetup ?? new OkDmaSetupRegion(),
            },
            new NoopEvidence(),
            splash: splash);

    internal sealed record FakeGuestMachine : IGuestMachine
    {
        public IWinlogonRegistry Winlogon { get; init; } = new NoopWinlogon();

        public IRegionSnapshot Region { get; init; } = new MatchingRegion();

        public IProcessHost Processes { get; init; } = new NoopProcesses();

        public ICheckpointStore Checkpoints { get; init; } = new NoopCheckpoints();

        public IAppxPackageManager? Appx { get; init; }

        public ISystemReboot? Reboot { get; init; }

        public IResidueCleaner? ResidueCleaner { get; init; }

        public IConnectivityProbe? Connectivity { get; init; }

        public IDmaSetupRegion? DmaSetup { get; init; } = new OkDmaSetupRegion();

        public IAssetDownload? AssetDownload { get; init; }

        public Func<string?>? ResolveScoopCmd { get; init; }

        public Func<bool> IsWslPlatformReadyCallback { get; init; } = () => false;

        public Action ApplyWorkstationQuietCallback { get; init; } = () => { };

        public Action SuppressWslOobeCallback { get; init; } = () => { };

        public bool IsWslPlatformReady() => IsWslPlatformReadyCallback();

        public void ApplyWorkstationQuiet() => ApplyWorkstationQuietCallback();

        public void SuppressWslOobe() => SuppressWslOobeCallback();
    }

    internal sealed class FakeAssetDownload : IAssetDownload
    {
        public string? ResultPath { get; init; }

        public Exception? Exception { get; init; }

        public List<(string Repo, IReadOnlyList<string> AssetNameCandidates)> Requests { get; } = [];

        public Task<string?> TryDownloadGitHubReleaseAssetAsync(
            string repo,
            IReadOnlyList<string> assetNameCandidates,
            CancellationToken ct = default)
        {
            Requests.Add((repo, assetNameCandidates));
            return Exception is null
                ? Task.FromResult(ResultPath)
                : Task.FromException<string?>(Exception);
        }
    }

    internal sealed class OkDmaSetupRegion : IDmaSetupRegion
    {
        public int EnsureCalls { get; private set; }

        public DmaSetupRegionEnsureResult EnsureIreland()
        {
            EnsureCalls++;
            return DmaSetupRegionEnsureResult.AlreadyOk;
        }
    }

    internal sealed class ScriptedDmaSetupRegion(params ScriptedDmaSetupRegion.DmaSetupStep[] steps) : IDmaSetupRegion
    {
        private readonly Queue<DmaSetupStep> _steps = new Queue<DmaSetupStep>(steps);

        public int EnsureCalls { get; private set; }

        public DmaSetupRegionEnsureResult EnsureIreland()
        {
            EnsureCalls++;
            if (_steps.Count == 0)
            {
                return DmaSetupRegionEnsureResult.AlreadyOk;
            }

            return _steps.Dequeue() switch
            {
                DmaSetupStep.AlreadyOkStep => DmaSetupRegionEnsureResult.AlreadyOk,
                DmaSetupStep.RepairedStep => DmaSetupRegionEnsureResult.Repaired,
                DmaSetupStep.ThrowStep t => throw new InvalidOperationException(t.Message),
                DmaSetupStep.ThrowUnauthorizedStep =>
                    throw new UnauthorizedAccessException("Attempted to perform an unauthorized operation."),
                _ => throw new InvalidOperationException("Unknown DMA setup step."),
            };
        }

        internal abstract record DmaSetupStep
        {
            public sealed record AlreadyOkStep : DmaSetupStep;

            public sealed record RepairedStep : DmaSetupStep;

            public sealed record ThrowStep(string Message) : DmaSetupStep;

            public sealed record ThrowUnauthorizedStep : DmaSetupStep;

            public static DmaSetupStep AlreadyOk { get; } = new AlreadyOkStep();

            public static DmaSetupStep Repaired { get; } = new RepairedStep();

            public static DmaSetupStep ThrowUnauthorized { get; } = new ThrowUnauthorizedStep();

            public static DmaSetupStep Throw(string message) => new ThrowStep(message);
        }
    }

    internal sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public int ExitCode { get; set; }

        public Func<string, IReadOnlyList<string>, ProcessStartResult>? OnRun { get; init; }

        public Task<ProcessStartResult> RunAsync(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return Task.FromResult(OnRun?.Invoke(fileName, arguments) ?? new ProcessStartResult(ExitCode));
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
        public List<ProvisioningEvidenceFile> Documents { get; } = [];
        public List<PackagesEvidenceFile> PackageDocuments { get; } = [];

        public EvidenceSnapshot Write(ProvisioningEvidenceFile document)
        {
            Documents.Add(document);
            return new EvidenceSnapshot(document.SchemaVersion, $"memory:{Documents.Count}");
        }

        public EvidenceSnapshot Write(PackagesEvidenceFile document)
        {
            PackageDocuments.Add(document);
            return new EvidenceSnapshot(document.SchemaVersion, $"memory:packages:{PackageDocuments.Count}");
        }
    }

    internal sealed class RecordingAppx : IAppxPackageManager
    {
        public List<AppxPackageInfo> Registered { get; } = [];
        public List<AppxPackageInfo> Provisioned { get; } = [];
        public List<string> RemovedFullNames { get; } = [];
        public List<string> DeprovisionedFamilyNames { get; } = [];
        public List<string> EnsuredDeprovisionedMarks { get; } = [];
        public List<string> RegisteredFamilyNames { get; } = [];

        public string? WingetPath { get; init; }

        public int EnsureSystemFullControlCalls { get; private set; }

        public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId) =>
            [.. Registered.Where(p => WinRTAppxPackageManager.MatchesCatalogId(p, catalogId))];

        public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId) =>
            [.. Provisioned.Where(p => WinRTAppxPackageManager.MatchesCatalogId(p, catalogId))];

        public Task RemovePackageAsync(string packageFullName, CancellationToken ct = default)
        {
            RemovedFullNames.Add(packageFullName);
            return Task.CompletedTask;
        }

        public Task DeprovisionPackageFamilyAsync(string packageFamilyName, CancellationToken ct = default)
        {
            DeprovisionedFamilyNames.Add(packageFamilyName);
            return Task.CompletedTask;
        }

        public void EnsureDeprovisionedMark(string packageFamilyName) =>
            EnsuredDeprovisionedMarks.Add(packageFamilyName);

        public Task RegisterPackageFamilyForCurrentUserAsync(
            string packageFamilyName,
            CancellationToken ct = default)
        {
            RegisteredFamilyNames.Add(packageFamilyName);
            return Task.CompletedTask;
        }

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

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => Shell;

        public void SetShell(string path) => Shell = path;

        public void GrantShellUnlockAccess(string username) { }
    }

    internal sealed class NoopProcesses : IProcessHost
    {
        public Task<ProcessStartResult> RunAsync(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default) =>
            Task.FromResult(new ProcessStartResult(0));
    }

    internal sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }

    internal sealed class NoopRegion : IRegionSnapshot
    {
        public void Apply(DmaSettleTarget target) { }

        public RegionState Read() => new(null, null, null, null);
    }

    internal sealed class NoopEvidence : IEvidenceSink
    {
        public EvidenceSnapshot Write(ProvisioningEvidenceFile document) =>
            new(document.SchemaVersion, "memory:1");

        public EvidenceSnapshot Write(PackagesEvidenceFile document) =>
            new(document.SchemaVersion, "memory:packages:1");
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
