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

        Console.Error.WriteLine("WinMint Provisioning: Shell tenure not implemented (ticket 04+).");
        return 1;
    }

    private static int RunMachineSetup()
    {
        string programData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint");
        Directory.CreateDirectory(programData);
        string logPath = Path.Combine(programData, "machine-setup.log");

        void Log(string line)
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

        try
        {
            string bundlePath = BundleLoader.DefaultGuestBundlePath;
            if (!File.Exists(bundlePath))
            {
                Log($"Bundle missing: {bundlePath}");
                return 1;
            }

            ProvisioningBundle bundle = BundleLoader.LoadFromFile(bundlePath);
            SessionEnvironment env = CreateEnvironment(bundlePath, Log);
            SessionResult result = ProvisioningSession.Run(SessionMode.MachineSetup, bundle, env);
            Log($"{result.FinalStatus.Code}: {result.FinalStatus.Message}");
            return result.Outcome == SessionOutcome.Complete ? 0 : 1;
        }
        catch (Exception ex)
        {
            Log($"machine_setup.crash: {ex}");
            return 1;
        }
    }

    private static SessionEnvironment CreateEnvironment(string bundlePath, Action<string> log)
    {
        IWinlogonRegistry winlogon = OperatingSystem.IsWindows()
            ? CreateWin32Winlogon()
            : throw new PlatformNotSupportedException("Machine setup requires Windows.");

        return new SessionEnvironment(
            Time: TimeProvider.System,
            Winlogon: winlogon,
            Region: new UnsupportedRegionSnapshot(),
            Processes: new UnsupportedProcessHost(),
            Splash: new UnsupportedSplashPresenter(),
            Checkpoints: new UnsupportedCheckpointStore(),
            Secrets: new FileSecretScrubber(bundlePath, log),
            Evidence: null);
    }

    [SupportedOSPlatform("windows")]
    private static Win32WinlogonRegistry CreateWin32Winlogon() => new();
}

internal sealed class UnsupportedRegionSnapshot : IRegionSnapshot; // ponytail: ticket 05

internal sealed class UnsupportedProcessHost : IProcessHost; // ponytail: ticket 06

internal sealed class UnsupportedSplashPresenter : ISplashPresenter; // ponytail: ticket 04

internal sealed class UnsupportedCheckpointStore : ICheckpointStore; // ponytail: ticket 08
