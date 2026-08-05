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
        public List<string> RegisteredFamilyNames { get; } = [];

        public string? WingetPath { get; init; }

        public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId) => [];

        public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId) => [];

        public void RemovePackage(string packageFullName) { }

        public void DeprovisionPackageFamily(string packageFamilyName) { }

        public void RegisterPackageFamilyForCurrentUser(string packageFamilyName) =>
            RegisteredFamilyNames.Add(packageFamilyName);

        public int EnsureSystemFullControlCalls { get; private set; }

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
}
