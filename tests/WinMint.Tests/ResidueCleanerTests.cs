using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class ResidueCleanerTests
{
    [Fact]
    public async Task Shell_Complete_invokes_ResidueCleaner_once()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingEvidenceSink evidence = new();
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            ShellEnv(winlogon, evidence, cleaner),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(1, cleaner.EraseCount);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
    }

    [Fact]
    public async Task Shell_Failed_does_not_invoke_ResidueCleaner()
    {
        RecordingResidueCleaner cleaner = new();
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            BundleFastSettle([]),
            ShellEnv(winlogon, new RecordingEvidenceSink(), cleaner, new NoopRegion()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal(0, cleaner.EraseCount);
    }

    [Fact]
    public void Win32ResidueCleaner_clears_autologon_and_deletes_payload_files()
    {
        string windir = Path.Combine(Path.GetTempPath(), "winmint-residue-" + Guid.NewGuid().ToString("N"));
        string winMint = Path.Combine(windir, "WinMint");
        string scripts = Path.Combine(windir, "Setup", "Scripts");
        Directory.CreateDirectory(winMint);
        Directory.CreateDirectory(scripts);
        File.WriteAllText(Path.Combine(winMint, "bundle.json"), "{}");
        File.WriteAllText(Path.Combine(winMint, "jobs.json"), "[]");
        File.WriteAllText(Path.Combine(winMint, "Supervisor.exe"), "stub");
        string setupComplete = Path.Combine(scripts, "SetupComplete.cmd");
        File.WriteAllText(setupComplete, "@echo off");

        bool autologonCleared = false;

        try
        {
            Win32ResidueCleaner cleaner = new(
                () => autologonCleared = true,
                windowsDirectory: windir);
            cleaner.TryEraseAfterComplete();

            Assert.True(autologonCleared);
            Assert.False(File.Exists(setupComplete));
            Assert.False(Directory.Exists(winMint));
        }
        finally
        {
            if (Directory.Exists(windir))
            {
                Directory.Delete(windir, recursive: true);
            }
        }
    }

    [Fact]
    public async Task Shell_Complete_swallows_ResidueCleaner_throw()
    {
        RecordingEvidenceSink evidence = new();
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            ShellEnv(winlogon, evidence, new ThrowingResidueCleaner()),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
    }

    private static ShellEnvironment ShellEnv(
        IWinlogonRegistry winlogon,
        IEvidenceSink evidence,
        IResidueCleaner cleaner,
        IRegionSnapshot? region = null) =>
        ProvisioningSessionTestFakes.Env(
            new FakeGuestMachine
            {
                Winlogon = winlogon,
                Region = region ?? new MatchingRegion(),
                ResidueCleaner = cleaner,
            },
            evidence);

    private sealed class RecordingResidueCleaner : IResidueCleaner
    {
        public int EraseCount { get; private set; }

        public void TryEraseAfterComplete() => EraseCount++;
    }

    private sealed class ThrowingResidueCleaner : IResidueCleaner
    {
        public void TryEraseAfterComplete() =>
            throw new InvalidOperationException("simulated residue failure");
    }
}
