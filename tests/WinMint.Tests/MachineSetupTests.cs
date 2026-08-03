using WinMint.Provisioning;

namespace WinMint.Tests;

public class MachineSetupTests
{
    private static string SupervisorPath => WinMint.Orchestrator.ImageServicing.ShellStampGuestPath;

    [Fact]
    public void MachineSetup_rejects_defaultuser0_with_AutoAdminLogon()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingSecretScrubber secrets = new();
        ProvisioningBundle bundle = MinimalBundle(ProvisioningSession.ForbiddenAutologonUser, "lab-only");

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            bundle,
            Env(winlogon, secrets),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("machineSetup.account.forbidden", result.FinalStatus.Code);
        Assert.False(winlogon.AutoAdminLogon);
        Assert.Null(winlogon.DefaultUserName);
        Assert.Equal(0, secrets.WipeCount);
    }

    [Fact]
    public void MachineSetup_stamps_autologon_and_wipes_secrets_when_Shell_ok()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingSecretScrubber secrets = new();
        ProvisioningBundle bundle = MinimalBundle("winmint", "lab-only");

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            bundle,
            Env(winlogon, secrets),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.True(winlogon.AutoAdminLogon);
        Assert.Equal("winmint", winlogon.DefaultUserName);
        Assert.Equal("lab-only", winlogon.DefaultPassword);
        Assert.Equal(SupervisorPath, winlogon.Shell);
        Assert.Equal(1, secrets.WipeCount);
        Assert.Equal("", secrets.LastBundle!.Account.Password);
    }

    [Fact]
    public void MachineSetup_restamps_Shell_when_mismatched_then_succeeds()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = "explorer.exe" };
        RecordingSecretScrubber secrets = new();
        ProvisioningBundle bundle = MinimalBundle("winmint", "lab-only");

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            bundle,
            Env(winlogon, secrets),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(SupervisorPath, winlogon.Shell);
        Assert.Equal(1, secrets.WipeCount);
    }

    [Fact]
    public void MachineSetup_fails_closed_when_Shell_restamp_does_not_stick()
    {
        FakeWinlogonRegistry winlogon = new()
        {
            Shell = "explorer.exe",
            ShellWriteNoOp = true,
        };
        RecordingSecretScrubber secrets = new();
        ProvisioningBundle bundle = MinimalBundle("winmint", "lab-only");

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            bundle,
            Env(winlogon, secrets),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("machineSetup.shell.verify_failed", result.FinalStatus.Code);
        Assert.Equal(1, secrets.WipeCount);
        Assert.True(winlogon.AutoAdminLogon);
    }

    [Fact]
    public void MachineSetup_cancelled_returns_Failed_not_throw()
    {
        using CancellationTokenSource cts = new();
        cts.Cancel();
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingSecretScrubber secrets = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            MinimalBundle("winmint", "lab-only"),
            Env(winlogon, secrets),
            cts.Token);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("machineSetup.cancelled", result.FinalStatus.Code);
        Assert.False(winlogon.AutoAdminLogon);
    }

    private static ProvisioningBundle MinimalBundle(string username, string password) =>
        new(
            Account: new AccountStamp(username, password),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: [],
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(IWinlogonRegistry winlogon, ISecretScrubber secrets) =>
        new(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: new NoopRegion(),
            Processes: new NoopProcesses(),
            Splash: new NoopSplash(),
            Checkpoints: new NoopCheckpoints(),
            Secrets: secrets);

    private sealed class FakeWinlogonRegistry : IWinlogonRegistry
    {
        public string? DefaultUserName { get; private set; }
        public string? DefaultPassword { get; private set; }
        public bool AutoAdminLogon { get; private set; }
        public string? Shell { get; set; }
        public bool ShellWriteNoOp { get; set; }

        public void SetAutoLogon(string username, string password)
        {
            DefaultUserName = username;
            DefaultPassword = password;
            AutoAdminLogon = true;
        }

        public string? GetDefaultUserName() => DefaultUserName;

        public bool GetAutoAdminLogon() => AutoAdminLogon;

        public string? GetShell() => Shell;

        public void SetShell(string path)
        {
            if (!ShellWriteNoOp)
            {
                Shell = path;
            }
        }
    }

    private sealed class RecordingSecretScrubber : ISecretScrubber
    {
        public int WipeCount { get; private set; }

        public ProvisioningBundle? LastBundle { get; private set; }

        public void Wipe(ProvisioningBundle bundle)
        {
            WipeCount++;
            LastBundle = bundle;
        }
    }

    private sealed class NoopRegion : IRegionSnapshot
    {
        public void Apply(DmaSettleTarget target) { }

        public RegionState Read() => new(null, null, null, null);
    }

    private sealed class NoopProcesses : IProcessHost
    {
        public ProcessStartResult Run(
            string fileName,
            IReadOnlyList<string> arguments,
            CancellationToken ct = default) =>
            new(0);
    }

    private sealed class NoopSplash : ISplashPresenter
    {
        public void Show() { }

        public void SetStatus(SessionStatus status) { }
    }

    private sealed class NoopCheckpoints : ICheckpointStore
    {
        public TenureState ReadTenure() => new(CheckpointInProgress: false, HeartbeatUtc: null);

        public void WriteHeartbeat(DateTimeOffset utcNow) { }
    }
}
