using WinMint.Provisioning;
using WinMint.Contracts;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class ShellTenureTests
{
    [Fact]
    public async Task Shell_Show_is_recorded_before_settle_begins()
    {
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();
        ProvisioningBundle bundle = MinimalBundle();

        SessionResult result = await ProvisioningSession.RunAsync(
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
        Assert.Single(evidence.Documents);
        Assert.Equal(ProvisioningSession.EvidenceSchemaVersion, evidence.Documents[0].SchemaVersion);
    }

    [Fact]
    public async Task Shell_emits_write_only_evidence_projection_shape()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-evidence-" + Guid.NewGuid().ToString("N"));
        try
        {
            FileEvidenceSink sink = new(dir);
            RecordingSplashPresenter splash = new();

            SessionResult result = await ProvisioningSession.RunAsync(
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
    public async Task Shell_pushes_in_memory_status_updates_to_presenter()
    {
        RecordingSplashPresenter splash = new();

        SessionResult result = await ProvisioningSession.RunAsync(
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
    public async Task Shell_fails_open_when_Evidence_sink_missing()
    {
        RecordingSplashPresenter splash = new();
        RecordingWinlogon winlogon = new() { Shell = SupervisorPath };

        SessionResult result = await ProvisioningSession.RunAsync(
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
            SupervisorShellPath: SupervisorPath);

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
            Evidence: evidence);
}
