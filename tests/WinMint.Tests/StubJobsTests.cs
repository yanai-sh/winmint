using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class StubJobsTests
{
    [Fact]
    public void Shell_invokes_stub_job_as_child_process_after_green_settle()
    {
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("smoke.stub.ready", "stub")]),
            Env(processes, evidence, splash: splash),
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
            Env(processes, evidence, splash: splash),
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
            Env(processes, evidence, splash: splash),
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
            Bundle(jobs: [new ProvisionJob("metal.browser", "browser")]),
            Env(processes, evidence, splash: new RecordingSplashPresenter()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.kind.unsupported", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
        Assert.Contains("jobs.kind.unsupported", evidence.Documents[0].Phases);
    }
}
