using System.Text.Json;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

public class MachineSetupTests
{
    [Fact]
    public void MachineSetup_rejects_defaultuser0_with_AutoAdminLogon()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingWipeSecrets secrets = new();
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
        RecordingWipeSecrets secrets = new();
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
        RecordingWipeSecrets secrets = new();
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
        RecordingWipeSecrets secrets = new();
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
        RecordingWipeSecrets secrets = new();

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
        RecordingWipeSecrets secrets = new();
        RecordingAppx appx = new();
        ProvisioningBundle bundle = MinimalBundle("winmint", "lab-only");

        SessionResult result = ProvisioningSession.Run(
            SessionMode.MachineSetup,
            bundle,
            Env(winlogon, secrets, appx: appx),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal(1, appx.EnsureSystemFullControlCalls);
    }

    [Fact]
    public void MachineSetup_removes_defaultuser0_via_LocalAccounts()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingWipeSecrets secrets = new();
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
    public void MachineSetup_wipes_bundle_password_on_disk()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-wipe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "bundle.json");
        try
        {
            File.WriteAllText(
                path,
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.SchemaVersion}}",
                  "supervisorPath": {{JsonSerializer.Serialize(WinMint.Orchestrator.ImageServicing.ShellStampGuestPath)}},
                  "username": "winmint",
                  "password": "lab-secret",
                  "dmaEnabled": true,
                  "settle": null
                }
                """);
            File.WriteAllText(
                Path.Combine(dir, "jobs.json"),
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.JobsSchemaVersion}}",
                  "jobs": []
                }
                """);

            ProvisioningBundle bundle = BundleLoader.LoadFromFile(path);
            Assert.Equal("lab-secret", bundle.Account.Password);

            FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
            SessionResult result = ProvisioningSession.Run(
                SessionMode.MachineSetup,
                bundle,
                Env(
                    winlogon,
                    wipeSecrets: _ => BundlePasswordWipe.WipeBundlePassword(path, null)),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Complete, result.Outcome);

            string onDisk = File.ReadAllText(path);
            Assert.DoesNotContain("lab-secret", onDisk, StringComparison.Ordinal);

            using JsonDocument doc = JsonDocument.Parse(onDisk);
            Assert.Equal("", doc.RootElement.GetProperty("password").GetString());
            Assert.Equal("winmint", doc.RootElement.GetProperty("username").GetString());

            ProvisioningBundle reloaded = BundleLoader.LoadFromFile(path);
            Assert.Equal("", reloaded.Account.Password);
        }
        finally
        {
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch
            {
                // ponytail: best-effort temp cleanup
            }
        }
    }

    [Fact]
    public void MachineSetup_completes_when_LocalAccounts_delete_throws()
    {
        FakeWinlogonRegistry winlogon = new() { Shell = SupervisorPath };
        RecordingWipeSecrets secrets = new();
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
        RecordingWipeSecrets? secrets = null,
        Action<ProvisioningBundle>? wipeSecrets = null,
        IAppxPackageManager? appx = null,
        ILocalAccounts? localAccounts = null) =>
        new(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: new NoopRegion(),
            Processes: new NoopProcesses(),
            Splash: new NoopSplash(),
            Checkpoints: new NoopCheckpoints(),
            WipeSecrets: wipeSecrets ?? secrets!.Wipe,
            Appx: appx,
            LocalAccounts: localAccounts);
}
