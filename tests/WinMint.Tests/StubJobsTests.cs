using WinMint.Orchestrator;
using WinMint.Provisioning;
using DmaSettleTarget = WinMint.Provisioning.DmaSettleTarget;

namespace WinMint.Tests;

public class StubJobsTests
{
    private static string SupervisorPath => ImageServicing.ShellStampGuestPath;

    [Fact]
    public void Shell_invokes_stub_job_as_child_process_after_green_settle()
    {
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("smoke.stub.ready", "stub")]),
            Env(processes, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Contains("Status:settle.ok", splash.Events);
        int settleOkAt = splash.Events.IndexOf("Status:settle.ok");
        int jobsBeginAt = splash.Events.IndexOf("Status:jobs.begin");
        Assert.True(jobsBeginAt > settleOkAt, "jobs begin after green settle");
        Assert.Single(processes.Starts);
        Assert.Equal("cmd.exe", processes.Starts[0].FileName, StringComparer.OrdinalIgnoreCase);
        Assert.Equal(["/c", "exit", "0"], processes.Starts[0].Arguments);
        Assert.Contains("jobs.begin", evidence.Documents[0].Phases);
        Assert.Contains("jobs.ok", evidence.Documents[0].Phases);
    }

    [Fact]
    public void Shell_runs_smoke_stub_catalog_in_order()
    {
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs:
            [
                new ProvisionJob("smoke.stub.ready", "stub"),
                new ProvisionJob("smoke.stub.complete", "stub"),
            ]),
            Env(processes, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(2, processes.Starts.Count);
        Assert.All(
            processes.Starts,
            s =>
            {
                Assert.Equal("cmd.exe", s.FileName, StringComparer.OrdinalIgnoreCase);
                Assert.Equal(["/c", "exit", "0"], s.Arguments);
            });
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
    }

    [Fact]
    public void Shell_job_nonzero_exit_fails_without_further_jobs()
    {
        RecordingProcessHost processes = new() { ExitCode = 7 };
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs:
            [
                new ProvisionJob("smoke.stub.ready", "stub"),
                new ProvisionJob("smoke.stub.complete", "stub"),
            ]),
            Env(processes, splash, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.failed", result.FinalStatus.Code);
        Assert.Single(processes.Starts);
        Assert.Contains("jobs.failed", evidence.Documents[0].Phases);
        Assert.DoesNotContain("jobs.ok", evidence.Documents[0].Phases);
    }

    [Fact]
    public void Shell_unsupported_job_kind_fails_without_spawn()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("winget.install", "winget")]),
            Env(processes, new RecordingSplashPresenter(), evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.kind.unsupported", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
        Assert.Contains("jobs.kind.unsupported", evidence.Documents[0].Phases);
    }

    private static ProvisioningBundle Bundle(IReadOnlyList<ProvisionJob> jobs) =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(
        IProcessHost processes,
        ISplashPresenter splash,
        IEvidenceSink evidence) =>
        new(
            Time: TimeProvider.System,
            Winlogon: new NoopWinlogon(),
            Region: new MatchingRegion(),
            Processes: processes,
            Splash: splash,
            Checkpoints: new NoopCheckpoints(),
            Secrets: new NoopSecrets(),
            Evidence: evidence);

    private sealed class RecordingProcessHost : IProcessHost
    {
        public List<(string FileName, IReadOnlyList<string> Arguments)> Starts { get; } = [];

        public int ExitCode { get; set; }

        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default)
        {
            Starts.Add((fileName, arguments));
            return new ProcessStartResult(ExitCode);
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

    private sealed class NoopWinlogon : IWinlogonRegistry
    {
        public void SetAutoLogon(string username, string password) { }

        public string? GetDefaultUserName() => null;

        public bool GetAutoAdminLogon() => false;

        public string? GetShell() => SupervisorPath;

        public void SetShell(string path) { }
    }

    private sealed class NoopCheckpoints : ICheckpointStore;

    private sealed class NoopSecrets : ISecretScrubber
    {
        public void Wipe(ProvisioningBundle bundle) { }
    }
}
