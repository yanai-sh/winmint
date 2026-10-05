using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

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

        SessionResult result = await ProvisioningSession.RunShellAsync(
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

            SessionResult result = await ProvisioningSession.RunShellAsync(
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
            Assert.Contains("\"shell.firstPaint\"", json, StringComparison.Ordinal);
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
    public void FileEvidenceSink_stamps_smokeRunId_from_sibling_file()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-smoke-run-" + Guid.NewGuid().ToString("N"));
        string evidenceDir = Path.Combine(root, "evidence");
        try
        {
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, FileEvidenceSink.SmokeRunIdFileName), "run-abc");
            FileEvidenceSink sink = new(evidenceDir);
            EvidenceSnapshot snap = sink.Write(
                new ProvisioningEvidenceFile(
                    SchemaVersion: ProvisioningSession.EvidenceSchemaVersion,
                    Outcome: "Complete",
                    StatusCode: "jobs.ok",
                    StatusMessage: "ok",
                    Phases: ["jobs.ok"]));
            string json = File.ReadAllText(snap.Path);
            Assert.Contains("\"smokeRunId\":\"run-abc\"", json.Replace(" ", ""), StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void FileEvidenceSink_omits_smokeRunId_when_stamp_missing()
    {
        string evidenceDir = Path.Combine(Path.GetTempPath(), "winmint-evidence-nostamp-" + Guid.NewGuid().ToString("N"));
        try
        {
            FileEvidenceSink sink = new(evidenceDir);
            EvidenceSnapshot snap = sink.Write(
                new ProvisioningEvidenceFile(
                    SchemaVersion: ProvisioningSession.EvidenceSchemaVersion,
                    Outcome: "Complete",
                    StatusCode: "jobs.ok",
                    StatusMessage: "ok",
                    Phases: ["jobs.ok"]));
            string json = File.ReadAllText(snap.Path);
            Assert.DoesNotContain("\"smokeRunId\": \"run-", json, StringComparison.Ordinal);
            Assert.Contains("\"smokeRunId\": null", json, StringComparison.Ordinal);
        }
        finally
        {
            if (Directory.Exists(evidenceDir))
            {
                Directory.Delete(evidenceDir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task Shell_pushes_in_memory_status_updates_to_presenter()
    {
        RecordingSplashPresenter splash = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            MinimalBundle(),
            Env(splash, new RecordingEvidenceSink()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("Status:shell.firstPaint", splash.Events);
        Assert.Contains("Status:settle.begin", splash.Events);
        Assert.Contains("Status:settle.ok", splash.Events);
        Assert.Contains("Status:jobs.ok", splash.Events);
        Assert.Equal("Show", splash.Events[0]);
    }

    private static ProvisioningBundle MinimalBundle() =>
        new(
            Account: new AccountStamp("winmint", ""),
            Dma: new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
            Jobs: [],
            Policy: SessionPolicy.SmokeDefaults,
            SupervisorShellPath: SupervisorPath);

    /// <summary>
    /// Winlogon launches the Supervisor as Shell. A tenure exit that skips unlock leaves a machine that
    /// logs on, exits, and logs on again — no desktop. Reboot must withhold so Supervisor resumes.
    /// </summary>
    [Theory]
    [InlineData(TenureExit.FailOpen, "explorer.exe", 1)] // MissingBundle / LoadFail / crash
    [InlineData(TenureExit.Reboot, ImageServicing.ShellStampGuestPath, 1)]
    [InlineData(TenureExit.Complete, "explorer.exe", 0)]
    public void Shell_stamp_follows_tenure_exit(TenureExit exit, string expectedShell, int expectedCode)
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };

        int code = ShellTenureEntry.Apply(winlogon, exit);

        Assert.Equal(expectedCode, code);
        Assert.Equal(expectedShell, winlogon.Shell);
    }

    private static ShellEnvironment Env(
        ISplashPresenter splash,
        IEvidenceSink evidence,
        IWinlogonRegistry? winlogon = null) =>
        ProvisioningSessionTestFakes.Env(
            new FakeGuestMachine
            {
                Winlogon = winlogon ?? new NoopWinlogon(),
            },
            evidence,
            splash: splash);
}
