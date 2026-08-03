using WinMint.Provisioning;

namespace WinMint.Tests;

public class ShellTenureTests
{
    private static string SupervisorPath => WinMint.Orchestrator.ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Shell_Show_is_recorded_before_settle_begins()
    {
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        ProvisioningBundle bundle = MinimalBundle();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            bundle,
            Env(splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        int showAt = splash.Events.IndexOf("Show");
        int settleAt = splash.Events.IndexOf("Status:settle.begin");
        Assert.True(showAt >= 0, "expected Splash.Show");
        Assert.True(settleAt >= 0, "expected settle.begin status");
        Assert.True(showAt < settleAt, "paint-before-settle order");
        Assert.Single(evidence.Written);
        Assert.Equal(ProvisioningSession.EvidenceSchemaVersion, evidence.Written[0].SchemaVersion);
    }

    [Fact]
    public void Shell_emits_write_only_evidence_projection_shape()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-evidence-" + Guid.NewGuid().ToString("N"));
        try
        {
            FileEvidenceSink sink = new(dir);
            RecordingSplashPresenter splash = new();

            SessionResult result = ProvisioningSession.Run(
                SessionMode.Shell,
                MinimalBundle(),
                Env(splash, sink),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Complete, result.Outcome);
            Assert.Single(result.EvidenceEmitted);
            EvidenceSnapshot snap = result.EvidenceEmitted[0];
            Assert.Equal(ProvisioningSession.EvidenceSchemaVersion, snap.SchemaVersion);
            Assert.True(File.Exists(snap.Path));

            string json = File.ReadAllText(snap.Path);
            Assert.Contains($"\"schemaVersion\": \"{ProvisioningSession.EvidenceSchemaVersion}\"", json, StringComparison.Ordinal);
            Assert.Contains("\"outcome\": \"Complete\"", json, StringComparison.Ordinal);
            Assert.Contains("\"shell.first_paint\"", json, StringComparison.Ordinal);
            Assert.Contains("\"settle.begin\"", json, StringComparison.Ordinal);
            Assert.DoesNotContain("setup-shell-control", json, StringComparison.Ordinal);
            Assert.DoesNotContain("setup-shell-status", json, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
    }

    [Fact]
    public void Shell_pushes_in_memory_status_updates_to_presenter()
    {
        RecordingSplashPresenter splash = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            MinimalBundle(),
            Env(splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:shell.first_paint", splash.Events);
        Assert.Contains("Status:settle.begin", splash.Events);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.Contains("Status:jobs.ok", splash.Events);
        Assert.Equal("Show", splash.Events[0]);
    }

    [Fact]
    public void Shell_fails_open_when_Evidence_sink_missing()
    {
        RecordingSplashPresenter splash = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            MinimalBundle(),
            Env(splash, evidence: null, winlogon),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.evidence.required", result.FinalStatus.Code);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
        Assert.Empty(result.EvidenceEmitted);
        Assert.Contains("Status:shell.evidence.required", splash.Events);
    }

    private static ProvisioningBundle MinimalBundle() =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: [],
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(
        ISplashPresenter splash,
        IEvidenceSink? evidence,
        IWinlogonRegistry? winlogon = null) =>
        new(
            Time: TimeProvider.System,
            Winlogon: winlogon ?? new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: new NoopProcesses(),
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
    }

    private sealed class RecordingSplashPresenter : ISplashPresenter
    {
        public List<string> Events { get; } = [];

        public void Show() => Events.Add("Show");

        public void SetStatus(SessionStatus status) => Events.Add($"Status:{status.Code}");
    }

    private sealed class RecordingEvidenceSink : IEvidenceSink
    {
        public List<EvidenceSnapshot> Written { get; } = [];

        public EvidenceSnapshot Write(ProvisioningEvidenceDocument document)
        {
            EvidenceSnapshot snap = new(document.SchemaVersion, $"memory:{Written.Count}");
            Written.Add(snap);
            return snap;
        }
    }

    private sealed class NoopWinlogon : IWinlogonRegistry
    {
        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => SupervisorPath;

        public void SetShell(string path) { }
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
}
