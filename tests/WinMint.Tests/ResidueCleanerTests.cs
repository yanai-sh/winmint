using Microsoft.Win32;

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
        Assert.Equal(1, cleaner.ScheduleCount);
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
        Assert.Equal(0, cleaner.ScheduleCount);
        Assert.Equal(0, cleaner.EraseCount);
    }

    [Fact]
    public async Task Shell_unlock_schedules_deferred_autologon_before_explorer_wait()
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
    public void ScheduleDeferredAutoLogonClear_writes_hkcu_runonce()
    {
        const string name = "WinMintClearAutoLogon";
        using RegistryKey key = Registry.CurrentUser.CreateSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\RunOnce")
            ?? throw new InvalidOperationException("HKCU RunOnce unavailable");
        key.DeleteValue(name, throwOnMissingValue: false);

        try
        {
            Win32WinlogonRegistry.ScheduleDeferredAutoLogonClear();
            object? value = key.GetValue(name);
            Assert.IsType<string>(value);
            string cmd = (string)value;
            Assert.Contains("AutoAdminLogon", cmd, StringComparison.Ordinal);
            Assert.Contains("reg.exe", cmd, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("Wallpaper", cmd, StringComparison.Ordinal);
            Assert.Contains("WallpaperStyle", cmd, StringComparison.Ordinal);
            Assert.Contains("TranscodedWallpaper", cmd, StringComparison.Ordinal);
            Assert.Contains("SearchboxTaskbarMode", cmd, StringComparison.Ordinal);
            Assert.DoesNotContain("TaskbarDa", cmd, StringComparison.Ordinal);
            Assert.Contains("TaskbarMn", cmd, StringComparison.Ordinal);
            Assert.Contains("ShowTaskViewButton", cmd, StringComparison.Ordinal);
            Assert.Contains("ShowCopilotButton", cmd, StringComparison.Ordinal);
            Assert.Contains("UpdatePerUserSystemParameters", cmd, StringComparison.Ordinal);
            Assert.Contains("timeout /t 10", cmd, StringComparison.Ordinal);
        }
        finally
        {
            key.DeleteValue(name, throwOnMissingValue: false);
        }
    }

    [Fact]
    public async Task Shell_schedule_throw_is_best_effort()
    {
        RecordingEvidenceSink evidence = new();
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            ShellEnv(winlogon, evidence, new ThrowingScheduleResidueCleaner()),
            TestContext.Current.CancellationToken);

        // ponytail: RunOnce arm is best-effort after unlock; throw must not fail the session
        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(ProvisioningSession.ExplorerShell, winlogon.Shell);
    }

    [Fact]
    public async Task Shell_Complete_swallows_erase_throw()
    {
        RecordingEvidenceSink evidence = new();
        RecordingWinlogon winlogon = new();

        SessionResult result = await ProvisioningSession.RunShellAsync(
            Bundle([]),
            ShellEnv(winlogon, evidence, new ThrowingEraseResidueCleaner()),
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
        public int ScheduleCount { get; private set; }

        public int EraseCount { get; private set; }

        public void TryScheduleDeferredAutoLogonClear() => ScheduleCount++;

        public void TryEraseAfterComplete() => EraseCount++;
    }

    private sealed class ThrowingScheduleResidueCleaner : IResidueCleaner
    {
        public void TryScheduleDeferredAutoLogonClear() =>
            throw new InvalidOperationException("simulated schedule failure");

        public void TryEraseAfterComplete()
        {
        }
    }

    private sealed class ThrowingEraseResidueCleaner : IResidueCleaner
    {
        public void TryScheduleDeferredAutoLogonClear()
        {
        }

        public void TryEraseAfterComplete() =>
            throw new InvalidOperationException("simulated residue failure");
    }
}
