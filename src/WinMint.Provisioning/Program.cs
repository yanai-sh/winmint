using System.Diagnostics;

namespace WinMint.Provisioning;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041))
        {
            NativeConsole.Hide();
        }

        if (args is ["--machine-setup", ..])
        {
            return await RunMachineSetupAsync().ConfigureAwait(false);
        }

        return await RunShellAsync().ConfigureAwait(false);
    }

    private static async Task<int> RunMachineSetupAsync()
    {
        string programData = ProgramDataRoot();
        Directory.CreateDirectory(programData);
        GuestFileLogger log = new(Path.Combine(programData, "machine-setup.log"));
        TryDisableReservedStorage(log);

        try
        {
            string bundlePath = BundleLoader.DefaultGuestBundlePath;
            if (!File.Exists(bundlePath))
            {
                GuestLog.BundleMissing(log, bundlePath);
                return 1;
            }

            BundleLoadResult loaded = BundleLoader.LoadFromFile(bundlePath);
            if (!loaded.IsOk)
            {
                GuestLog.Failure(log, loaded.Error.Code, loaded.Error.Message);
                return 1;
            }

            ProvisioningBundle bundle = loaded.Value;
            MachineSetupEnvironment env = new(
                Winlogon: Winlogon(),
                WipeSecrets: _ => BundlePasswordWipe.WipeBundlePassword(bundlePath, logger: log),
                Appx: new WinRTAppxPackageManager(logger: log),
                LocalAccounts: new Win32LocalAccounts(),
                DmaSetup: new Win32DmaSetupRegion(),
                StampOobeComplete: Win32OobeOverlay.TryStampSetupComplete);
            SessionResult result = await ProvisioningSession.RunMachineSetupAsync(bundle, env)
                .ConfigureAwait(false);
            GuestLog.SessionStatus(log, result.FinalStatus.Code, result.FinalStatus.Message);
            return result.Outcome == SessionOutcome.Complete ? 0 : 1;
        }
        catch (Exception ex)
        {
            GuestLog.MachineSetupCrash(log, ex);
            return 1;
        }
    }

    private static async Task<int> RunShellAsync()
    {
        string programData = ProgramDataRoot();
        Directory.CreateDirectory(programData);
        GuestFileLogger log = new(Path.Combine(programData, "shell.log"));
        string evidenceDir = Path.Combine(programData, "evidence");

        GdiSplashPresenter? splash = null;
        try
        {
            string bundlePath = BundleLoader.DefaultGuestBundlePath;
            if (!File.Exists(bundlePath))
            {
                GuestLog.BundleMissing(log, bundlePath);
                return FailOpenShell(log);
            }

            if (!OperatingSystem.IsWindows())
            {
                throw new PlatformNotSupportedException("Shell tenure requires Windows.");
            }

            splash = new GdiSplashPresenter();
            BundleLoadResult loaded = BundleLoader.LoadFromFile(bundlePath);
            if (!loaded.IsOk)
            {
                GuestLog.Failure(log, loaded.Error.Code, loaded.Error.Message);
                return FailOpenShell(log);
            }

            ProvisioningBundle bundle = loaded.Value;
            Win32WinlogonRegistry winlogon = Winlogon();
            ShellEnvironment env = new(
                Time: TimeProvider.System,
                Guest: new Win32GuestMachine(programData, winlogon, log),
                Splash: splash,
                Evidence: new FileEvidenceSink(evidenceDir));
            SessionResult result = await ProvisioningSession.RunShellAsync(bundle, env)
                .ConfigureAwait(false);
            GuestLog.SessionStatus(log, result.FinalStatus.Code, result.FinalStatus.Message);
            foreach (EvidenceSnapshot snap in result.EvidenceEmitted)
            {
                GuestLog.Evidence(log, snap.SchemaVersion, snap.Path);
            }

            // Session already stamped Complete/Failed/Reboot; Apply is the durable exit seam
            // (idempotent unlock, withhold on Reboot) so Program cannot skip Shell policy.
            return ShellTenureEntry.Apply(winlogon, ShellTenureEntry.FromSession(result.Outcome));
        }
        catch (Exception ex)
        {
            GuestLog.ShellCrash(log, ex);
            return FailOpenShell(log);
        }
        finally
        {
            splash?.Dispose();
        }
    }

    /// <summary>
    /// Catastrophic Shell exits that never produced a session outcome (missing bundle, load fail, crash).
    /// Must unlock — never leave Supervisor as a dead shell. Not for Reboot.
    /// </summary>
    private static int FailOpenShell(GuestFileLogger log)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                return ShellTenureEntry.Apply(Winlogon(), TenureExit.FailOpen);
            }
        }
        catch (Exception ex)
        {
            // ponytail: nothing left to try — MachineSetup grants the unlock ACL (GrantShellUnlockAccess),
            // so this only fails when that grant did not land, and the log is the operator's only clue.
            GuestLog.ShellCrash(log, ex);
        }

        return 1;
    }

    private static string ProgramDataRoot() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "WinMint");

    private static void TryDisableReservedStorage(GuestFileLogger log)
    {
        try
        {
            string dism = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32",
                "dism.exe");
            ProcessExitStatus status = Process.Run(
                dism,
                ["/Online", "/Set-ReservedStorageState", "/State:Disabled"],
                silent: true,
                timeout: TimeSpan.FromMinutes(2));
            if (status.Canceled)
            {
                GuestLog.ReservedStorageDismFailed(log, "timed out");
                return;
            }

            if (status.ExitCode != 0)
            {
                GuestLog.ReservedStorageDismNonZero(log, status.ExitCode);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            GuestLog.ReservedStorageDismFailed(log, ex.Message);
        }
    }

    private static Win32WinlogonRegistry Winlogon() =>
        OperatingSystem.IsWindows()
            ? new Win32WinlogonRegistry()
            : throw new PlatformNotSupportedException("Provisioning requires Windows.");

}
