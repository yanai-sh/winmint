using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class ShellChromeJobTests
{
    [Fact]
    public void Plan_emits_shell_chrome_after_wsl()
    {
        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            ["Anysphere.Cursor"],
            [],
            [],
            [],
            ["FedoraLinux"],
            [],
            [],
            []);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "arm64" });

        Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);
        IReadOnlyList<ProvisionJob> jobs = result.Value.Jobs.Jobs;
        int lastWsl = jobs.ToList().FindLastIndex(j => j.Kind is ProvisionJobKind.Wsl or ProvisionJobKind.WslPlatform);
        int chrome = jobs.ToList().FindIndex(j => j.Id == "shell.chrome" && j.Kind == ProvisionJobKind.ShellChrome);
        Assert.True(lastWsl >= 0);
        Assert.True(chrome > lastWsl);
    }

    [Fact]
    public async Task Shell_chrome_records_request_and_emits_phase()
    {
        FakeGuestMachine guest = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle(jobs: [new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome)]),
            Env(guest, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        ShellChromeRequest request = Assert.Single(guest.ShellChromeRequests);
        Assert.False(request.FailOpen);
        Assert.Contains("shell.chrome", evidence.Documents[^1].Phases);
    }

    [Fact]
    public async Task Shell_chrome_fails_closed_when_apply_returns_false()
    {
        FakeGuestMachine guest = new()
        {
            ApplyShellChromeCallback = request => !request.FailOpen ? false : true,
        };
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle(jobs: [new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome)]),
            Env(guest, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.DoesNotContain("shell.chrome", evidence.Documents[^1].Phases);
    }
}
