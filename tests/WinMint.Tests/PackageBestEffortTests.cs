using WinMint.Provisioning;
using WinMint.Contracts;
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
        string evidenceDir = Path.Combine(Path.GetTempPath(), "WinMintTests", Guid.NewGuid().ToString("N"));

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("winget.jqlang.jq", ProvisionJobKind.Winget, PackageId: "jqlang.jq")]),
            Env(processes, evidence, appx: appx) with { EvidenceDirectory = evidenceDir },
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Contains("package failure", result.FinalStatus.Message, StringComparison.OrdinalIgnoreCase);
        string packagesEvidence = Path.Combine(evidenceDir, "packages.evidence.json");
        Assert.True(File.Exists(packagesEvidence));
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
