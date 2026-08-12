using WinMint.Orchestrator;
using WinMint.Contracts;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class WorkstationQuietTests
{
    [Fact]
    public void Plan_always_emits_workstation_quiet_job()
    {
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(Lab());
        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Id == "workstation.quiet" && j.Kind == ProvisionJobKind.WorkstationQuiet);
    }

    [Fact]
    public async Task Shell_workstation_quiet_invokes_applier()
    {
        bool applied = false;
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("workstation.quiet", ProvisionJobKind.WorkstationQuiet)]),
            Env(processes, evidence, applyWorkstationQuiet: () => applied = true),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.True(applied);
        Assert.Contains("jobs.workstation.quiet", evidence.Documents[^1].Phases);
    }

    private static Profile Lab() =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget(true, "en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            null);
}
