namespace WinMint.Provisioning;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
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
            SessionEnvironment env = CreateEnvironment(bundlePath, log, splash: null);
            SessionResult result = await ProvisioningSession.RunAsync(SessionMode.MachineSetup, bundle, env)
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
                return 1;
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
                return 1;
            }

            ProvisioningBundle bundle = loaded.Value;
            SessionEnvironment env = CreateEnvironment(
                bundlePath,
                log,
                splash,
                new FileEvidenceSink(evidenceDir),
                new FileCheckpointStore(programData),
                evidenceDirectory: evidenceDir);
            SessionResult result = await ProvisioningSession.RunAsync(SessionMode.Shell, bundle, env)
                .ConfigureAwait(false);
            GuestLog.SessionStatus(log, result.FinalStatus.Code, result.FinalStatus.Message);
            foreach (EvidenceSnapshot snap in result.EvidenceEmitted)
            {
                GuestLog.Evidence(log, snap.SchemaVersion, snap.Path);
            }

            return result.Outcome == SessionOutcome.Complete ? 0 : 1;
        }
        catch (Exception ex)
        {
            GuestLog.ShellCrash(log, ex);
            return 1;
        }
        finally
        {
            splash?.Dispose();
        }
    }

    private static string ProgramDataRoot() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "WinMint");

    private static SessionEnvironment CreateEnvironment(
        string bundlePath,
        GuestFileLogger log,
        ISplashPresenter? splash,
        IEvidenceSink? evidence = null,
        ICheckpointStore? checkpoints = null,
        string? evidenceDirectory = null)
    {
        IWinlogonRegistry winlogon = OperatingSystem.IsWindows()
            ? new Win32WinlogonRegistry()
            : throw new PlatformNotSupportedException("Provisioning requires Windows.");

        return new SessionEnvironment(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: new Win32RegionSnapshot(),
            Processes: new Win32ProcessHost(),
            Splash: splash ?? new NoopSplashPresenter(),
            Checkpoints: checkpoints ?? new FileCheckpointStore(ProgramDataRoot()),
            WipeSecrets: _ => BundlePasswordWipe.WipeBundlePassword(bundlePath, logger: log),
            Evidence: evidence,
            Appx: new WinRTAppxPackageManager(logger: log),
            Reboot: new Win32SystemReboot(),
            LocalAccounts: new Win32LocalAccounts(),
            ResolveScoopCmd: TryResolveScoopShim,
            ResidueCleaner: new Win32ResidueCleaner(winlogon, logger: log),
            Connectivity: new WindowsConnectivityProbe(),
            EvidenceDirectory: evidenceDirectory,
            DmaSetup: new Win32DmaSetupRegion());
    }

    /// <summary>Default Scoop shim after official bootstrap (PROVISIONINGSESSION). Host-owned File.Exists.</summary>
    private static string? TryResolveScoopShim()
    {
        string candidate = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims",
            "scoop.cmd");
        return File.Exists(candidate) ? candidate : null;
    }
}

/// <summary>Machine setup has no splash surface; Shell wires <see cref="GdiSplashPresenter"/>.</summary>
internal sealed class NoopSplashPresenter : ISplashPresenter
{
    public void Show() { }

    public void SetStatus(SessionStatus status) { }
}
