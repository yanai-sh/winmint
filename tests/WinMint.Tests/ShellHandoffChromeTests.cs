using WinMint.Contracts;
using WinMint.Provisioning;

using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class ShellHandoffChromeTests
{
    [Fact]
    public async Task Shell_Complete_waits_for_explorer_reapplies_chrome_then_erases()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingEvidenceSink evidence = new();
        RecordingWinlogon winlogon = new();
        ManualTimeProvider time = new();
        int explorerChecks = 0;
        FakeGuestMachine guest = new()
        {
            Winlogon = winlogon,
            ResidueCleaner = cleaner,
            IsExplorerProcessRunningCallback = () => ++explorerChecks >= 2,
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            Env(guest, evidence, time: time),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(1, cleaner.ScheduleCount);
        Assert.Equal(1, cleaner.EraseCount);
        Assert.Single(guest.ShellChromeRequests);
        Assert.False(guest.ShellChromeRequests[0].FailOpen);
        Assert.Contains("shell.explorerReady", evidence.Documents[^1].Phases);
        Assert.Contains("shell.chrome.live", evidence.Documents[^1].Phases);
        Assert.Contains("shell.chrome.settled", evidence.Documents[^1].Phases);
        Assert.True(explorerChecks >= 2);
    }

    [Fact]
    public async Task Shell_explorer_missing_fails_open_without_residue_erase()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingEvidenceSink evidence = new();
        ManualTimeProvider time = new();
        FakeGuestMachine guest = new()
        {
            Winlogon = new RecordingWinlogon(),
            ResidueCleaner = cleaner,
            IsExplorerProcessRunningCallback = static () => false,
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]) with
            {
                Policy = SessionPolicy.SmokeDefaults with
                {
                    SettleDeadline = TimeSpan.FromSeconds(4),
                    SettlePollInterval = TimeSpan.FromSeconds(1),
                    FailedDwell = TimeSpan.Zero,
                },
            },
            Env(guest, evidence, time: time),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.explorerMissing", result.FinalStatus.Code);
        Assert.Equal(1, cleaner.ScheduleCount);
        Assert.Equal(0, cleaner.EraseCount);
        Assert.DoesNotContain(guest.ShellChromeRequests, r => !r.FailOpen);
        Assert.Equal("Failed", evidence.Documents[^1].Outcome);
    }

    [Fact]
    public async Task Shell_live_chrome_failure_fails_open_without_residue_erase()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingEvidenceSink evidence = new();
        ManualTimeProvider time = new();
        FakeGuestMachine guest = new()
        {
            Winlogon = new RecordingWinlogon(),
            ResidueCleaner = cleaner,
            ApplyShellChromeCallback = static _ => false,
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            Env(guest, evidence, time: time),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.chrome.liveFailed", result.FinalStatus.Code);
        Assert.Equal(1, cleaner.ScheduleCount);
        Assert.Equal(0, cleaner.EraseCount);
        Assert.Contains(guest.ShellChromeRequests, r => !r.FailOpen);
        Assert.Equal("Failed", evidence.Documents[^1].Outcome);
    }

    [Fact]
    public async Task Shell_chrome_job_then_live_pass_applies_twice_before_erase()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingEvidenceSink evidence = new();
        ManualTimeProvider time = new();
        FakeGuestMachine guest = new()
        {
            Winlogon = new RecordingWinlogon(),
            ResidueCleaner = cleaner,
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([new ProvisionJob("shell.chrome", ProvisionJobKind.ShellChrome)]),
            Env(guest, evidence, time: time),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(2, guest.ShellChromeRequests.Count);
        Assert.All(guest.ShellChromeRequests, r => Assert.False(r.FailOpen));
        Assert.Equal(1, cleaner.ScheduleCount);
        Assert.Equal(1, cleaner.EraseCount);
        Assert.Contains("shell.chrome", evidence.Documents[^1].Phases);
        Assert.Contains("shell.chrome.live", evidence.Documents[^1].Phases);
        Assert.Contains("shell.chrome.settled", evidence.Documents[^1].Phases);
    }

    [Fact]
    public async Task Shell_live_chrome_unstable_fails_open_without_residue_erase()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingEvidenceSink evidence = new();
        ManualTimeProvider time = new();
        FakeGuestMachine guest = new()
        {
            Winlogon = new RecordingWinlogon(),
            ResidueCleaner = cleaner,
            IsLiveShellChromeStickyCallback = static () => false,
        };

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]) with
            {
                Policy = SessionPolicy.SmokeDefaults with
                {
                    SettleDeadline = TimeSpan.FromSeconds(4),
                    SettlePollInterval = TimeSpan.FromSeconds(1),
                    FailedDwell = TimeSpan.Zero,
                },
            },
            Env(guest, evidence, time: time),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("shell.chrome.liveUnstable", result.FinalStatus.Code);
        Assert.Equal(1, cleaner.ScheduleCount);
        Assert.Equal(0, cleaner.EraseCount);
        Assert.Contains(guest.ShellChromeRequests, r => !r.FailOpen);
    }

    private sealed class RecordingResidueCleaner : IResidueCleaner
    {
        public int ScheduleCount { get; private set; }

        public int EraseCount { get; private set; }

        public void TryScheduleDeferredAutoLogonClear() => ScheduleCount++;

        public void TryEraseAfterComplete() => EraseCount++;
    }
}
