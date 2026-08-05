using System.Runtime.Versioning;

namespace WinMint.Provisioning;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args is ["--machine-setup", ..])
        {
            return RunMachineSetup();
        }

        return RunShell();
    }

    private static int RunMachineSetup()
    {
        string programData = ProgramDataRoot();
        Directory.CreateDirectory(programData);
        string logPath = Path.Combine(programData, "machine-setup.log");

        void Log(string line) => AppendLog(logPath, line);

        try
        {
            string bundlePath = BundleLoader.DefaultGuestBundlePath;
            if (!File.Exists(bundlePath))
            {
                Log($"Bundle missing: {bundlePath}");
                return 1;
            }

            ProvisioningBundle bundle = BundleLoader.LoadFromFile(bundlePath);
            SessionEnvironment env = CreateEnvironment(bundlePath, Log, splash: null);
            SessionResult result = ProvisioningSession.Run(SessionMode.MachineSetup, bundle, env);
            Log($"{result.FinalStatus.Code}: {result.FinalStatus.Message}");
            return result.Outcome == SessionOutcome.Complete ? 0 : 1;
        }
        catch (Exception ex)
        {
            Log($"machineSetup.crash: {ex}");
            return 1;
        }
    }

    private static int RunShell()
    {
        string programData = ProgramDataRoot();
        Directory.CreateDirectory(programData);
        string logPath = Path.Combine(programData, "shell.log");
        string evidenceDir = Path.Combine(programData, "evidence");

        void Log(string line) => AppendLog(logPath, line);

        GdiSplashPresenter? splash = null;
        try
        {
            string bundlePath = BundleLoader.DefaultGuestBundlePath;
            if (!File.Exists(bundlePath))
            {
                Log($"Bundle missing: {bundlePath}");
                return 1;
            }

            if (!OperatingSystem.IsWindows())
            {
                throw new PlatformNotSupportedException("Shell tenure requires Windows.");
            }

            splash = new GdiSplashPresenter();
            ProvisioningBundle bundle = BundleLoader.LoadFromFile(bundlePath);
            SessionEnvironment env = CreateEnvironment(
                bundlePath,
                Log,
                splash,
                new FileEvidenceSink(evidenceDir),
                new FileCheckpointStore(programData));
            SessionResult result = ProvisioningSession.Run(SessionMode.Shell, bundle, env);
            Log($"{result.FinalStatus.Code}: {result.FinalStatus.Message}");
            foreach (EvidenceSnapshot snap in result.EvidenceEmitted)
            {
                Log($"evidence: {snap.SchemaVersion} -> {snap.Path}");
            }

            return result.Outcome == SessionOutcome.Complete ? 0 : 1;
        }
        catch (Exception ex)
        {
            Log($"shell.crash: {ex}");
            return 1;
        }
        finally
        {
            splash?.Dispose();
        }
    }

    private static string ProgramDataRoot() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "WinMint");

    private static void AppendLog(string logPath, string line)
    {
        string stamped = $"{DateTimeOffset.UtcNow:o} {line}";
        Console.Error.WriteLine(stamped);
        try
        {
            File.AppendAllText(logPath, stamped + Environment.NewLine);
        }
        catch
        {
            // ponytail: best-effort ProgramData log
        }
    }

    private static SessionEnvironment CreateEnvironment(
        string bundlePath,
        Action<string> log,
        ISplashPresenter? splash,
        IEvidenceSink? evidence = null,
        ICheckpointStore? checkpoints = null)
    {
        IWinlogonRegistry winlogon = OperatingSystem.IsWindows()
            ? CreateWin32Winlogon()
            : throw new PlatformNotSupportedException("Provisioning requires Windows.");

        return new SessionEnvironment(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: CreateRegion(),
            Processes: new Win32ProcessHost(),
            Splash: splash ?? new NoopSplashPresenter(),
            Checkpoints: checkpoints ?? new FileCheckpointStore(ProgramDataRoot()),
            WipeSecrets: new FileSecretScrubber(bundlePath, log).Wipe,
            Evidence: evidence,
            Appx: CreateAppxPackageManager(log),
            Reboot: CreateSystemReboot(),
            LocalAccounts: CreateLocalAccounts(),
            ResolveScoopCmd: TryResolveScoopShim);
    }

    /// <summary>Default Scoop shim after official bootstrap (research 2026-08-04). Host-owned File.Exists.</summary>
    private static string? TryResolveScoopShim()
    {
        string candidate = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims",
            "scoop.cmd");
        return File.Exists(candidate) ? candidate : null;
    }

    [SupportedOSPlatform("windows10.0.19041.0")]
    private static WinRTAppxPackageManager CreateAppxPackageManager(Action<string> log) => new(log);

    [SupportedOSPlatform("windows")]
    private static Win32WinlogonRegistry CreateWin32Winlogon() => new();

    [SupportedOSPlatform("windows")]
    private static Win32RegionSnapshot CreateRegion() => new();

    [SupportedOSPlatform("windows")]
    private static Win32SystemReboot CreateSystemReboot() => new();

    [SupportedOSPlatform("windows")]
    private static Win32LocalAccounts CreateLocalAccounts() => new();
}

/// <summary>Machine setup has no splash surface; Shell wires <see cref="GdiSplashPresenter"/>.</summary>
internal sealed class NoopSplashPresenter : ISplashPresenter
{
    public void Show() { }

    public void SetStatus(SessionStatus status) { }
}
