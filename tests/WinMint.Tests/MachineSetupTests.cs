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

    [Fact]
    public void MachineSetup_repairs_winget_framework_acls_when_Appx_present()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingSecretScrubber secrets = new();
        RecordingAppx appx = new();
        ProvisioningBundle bundle = MinimalBundle("winmint", "lab-only");

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            bundle,
            Env(winlogon, secrets, appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(1, appx.EnsureSystemFullControlCalls);
    }

    [Fact]
    public void MachineSetup_removes_defaultuser0_via_LocalAccounts()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingSecretScrubber secrets = new();
        RecordingLocalAccounts accounts = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            MinimalBundle("winmint", "lab-only"),
            Env(winlogon, secrets, localAccounts: accounts),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal([ProvisioningSession.ForbiddenAutologonUser], accounts.Deleted);
    }

    [Fact]
    public void MachineSetup_completes_when_LocalAccounts_delete_throws()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingSecretScrubber secrets = new();
        ThrowingLocalAccounts accounts = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            MinimalBundle("winmint", "lab-only"),
            Env(winlogon, secrets, localAccounts: accounts),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.True(winlogon.AutoAdminLogon);
        Assert.Equal(1, secrets.WipeCount);
    }

    private static ProvisioningBundle MinimalBundle(string username, string password) =>
        new(
            Account: new AccountStamp(username, password),
            Dma: new DmaSettleTarget(Enabled: true, "en-GB", 242, "GMT Standard Time", true),
            Jobs: [],
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(SupervisorPath));

    private static SessionEnvironment Env(
        IWinlogonRegistry winlogon,
        RecordingSecretScrubber secrets,
        IAppxPackageManager? appx = null,
        ILocalAccounts? localAccounts = null) =>
        new(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: new NoopRegion(),
            Processes: new NoopProcesses(),
            Splash: new NoopSplash(),
            Checkpoints: new NoopCheckpoints(),
            WipeSecrets: secrets.Wipe,
            Appx: appx,
            LocalAccounts: localAccounts);

    private sealed class RecordingLocalAccounts : ILocalAccounts
    {
        public List<string> Deleted { get; } = [];

        public void TryDeleteLocalUserAndProfile(string username) => Deleted.Add(username);
    }

    private sealed class ThrowingLocalAccounts : ILocalAccounts
    {
        public void TryDeleteLocalUserAndProfile(string username) =>
            throw new InvalidOperationException("simulated delete failure");
    }

    private sealed class RecordingAppx : IAppxPackageManager
    {
        public int EnsureSystemFullControlCalls { get; private set; }

        public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId) => [];

        public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId) => [];

        public void RemovePackage(string packageFullName) { }

        public void DeprovisionPackageFamily(string packageFamilyName) { }

        public void RegisterPackageFamilyForCurrentUser(string packageFamilyName) { }

        public void EnsureSystemFullControlOnWingetFrameworkPackages() => EnsureSystemFullControlCalls++;

        public string? TryResolveWingetExecutablePath() => null;
    }

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

        public void GrantShellUnlockAccess(string username) { }
    }

    private sealed class RecordingSecretScrubber
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

        public void WriteCheckpoint(CheckpointState state) { }

        public CheckpointState? TryReadCheckpoint() => null;

        public void ClearCheckpoint() { }
    }
}
