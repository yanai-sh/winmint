using WinMint.Provisioning;
using WinMint.Contracts;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class StubJobsTests
{
    [Fact]
    public async Task Shell_invokes_stub_job_as_child_process_after_green_settle()
    {
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub)]),
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
    public async Task Shell_runs_smoke_stub_catalog_in_order()
    {
        RecordingProcessHost processes = new();
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs:
            [
                new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub),
                new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub),
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
    public async Task Shell_job_nonzero_exit_fails_without_further_jobs()
    {
        RecordingProcessHost processes = new() { ExitCode = 7 };
        RecordingSplashPresenter splash = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs:
            [
                new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub),
                new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub),
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
    public async Task Shell_reserved_storage_disable_completes_without_unelevated_dism()
    {
        RecordingProcessHost processes = new() { ExitCode = 740 };
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("reservedStorage.disable", ProvisionJobKind.ReservedStorageDisable)]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.DoesNotContain(
            processes.Starts,
            s => s.FileName.Contains("dism", StringComparison.OrdinalIgnoreCase));
    }

}
