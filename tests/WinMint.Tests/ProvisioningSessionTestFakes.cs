using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

/// <summary>Shared S3 fakes for metal job tests (Scoop / WSL / …).</summary>
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

    internal static SessionEnvironment Env(IProcessHost processes, IEvidenceSink evidence) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: processes,
            Splash: new RecordingSplashPresenter(),
            Checkpoints: new NoopCheckpoints(),
            Secrets: new NoopSecrets(),
            Evidence: evidence);

    internal sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public Func<string, IReadOnlyList<string>, ProcessStartResult>? OnRun { get; init; }

        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return OnRun?.Invoke(fileName, arguments) ?? new ProcessStartResult(0);
        }
    }

    internal sealed class RecordingSplashPresenter : ISplashPresenter
    {
        public void Show() { }

        public void SetStatus(SessionStatus status) { }
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

    internal sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }

    internal sealed class NoopSecrets : ISecretScrubber
    {
        public void Wipe(ProvisioningBundle bundle) { }
    }
}
