using WinMint.Contracts;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class PackageBestEffortTests
{
    [Fact]
    public async Task Shell_winget_failure_continues_when_not_strict()
    {
        RecordingProcessHost processes = new() { ExitCode = 1 };
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]),
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("package failure", result.FinalStatus.Message, StringComparison.OrdinalIgnoreCase);
        PackagesEvidenceFile packagesEvidence = Assert.Single(evidence.PackageDocuments);
        Assert.Equal("winget.jqlang.jq", Assert.Single(packagesEvidence.Failures).JobId);
    }

    [Fact]
    public async Task Shell_winget_failure_fails_closed_when_strict()
    {
        RecordingProcessHost processes = new() { ExitCode = 1 };
        RecordingEvidenceSink evidence = new();
        RecordingAppx appx = new() { WingetPath = @"C:\Tools\winget.exe" };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]) with { PackageStrict = true },
            Env(processes, evidence, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.failed", result.FinalStatus.Code);
    }
}
