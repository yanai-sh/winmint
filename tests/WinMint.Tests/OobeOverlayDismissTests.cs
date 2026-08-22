using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class OobeOverlayDismissTests
{
    [Fact]
    public async Task Shell_Complete_invokes_dismiss_and_records_phase()
    {
        int dismissCount = 0;
        RecordingEvidenceSink evidence = new();
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            ShellEnv(
                winlogon,
                evidence,
                onDismiss: () => dismissCount++),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(1, dismissCount);
        ProvisioningEvidenceFile doc = evidence.Documents[0];
        Assert.Contains("oobe.dismiss", doc.Phases);
    }

    [Fact]
    public async Task Shell_Failed_invokes_dismiss_after_fail_open_unlock()
    {
        int dismissCount = 0;
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle([]),
            ShellEnv(
                winlogon,
                new RecordingEvidenceSink(),
                onDismiss: () => dismissCount++,
                region: new NoopRegion()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal(1, dismissCount);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
    }

    [Fact]
    public async Task Shell_Complete_swallows_dismiss_throw()
    {
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            ShellEnv(
                winlogon,
                new RecordingEvidenceSink(),
                onDismiss: () => throw new InvalidOperationException("simulated dismiss failure")),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
    }

    private static ShellEnvironment ShellEnv(
        IWinlogonRegistry winlogon,
        IEvidenceSink evidence,
        Action onDismiss,
        IRegionSnapshot? region = null) =>
        ProvisioningSessionTestFakes.Env(
            new FakeGuestMachine
            {
                Winlogon = winlogon,
                Region = region ?? new MatchingRegion(),
                TryDismissOobeOverlayCallback = onDismiss,
            },
            evidence);
}
