using Microsoft.Extensions.Logging;

namespace WinMint.Provisioning;

/// <summary>Production Shell-tenure adapter over the live Windows guest.</summary>
public sealed class Win32GuestMachine : IGuestMachine
{
    public Win32GuestMachine(
        string programData,
        Win32WinlogonRegistry winlogon,
        ILogger? logger = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(programData);
        ArgumentNullException.ThrowIfNull(winlogon);

        Winlogon = winlogon;
        Region = new Win32RegionSnapshot();
        Processes = new Win32ProcessHost();
        Checkpoints = new FileCheckpointStore(programData);
        Appx = new WinRTAppxPackageManager(logger: logger);
        Reboot = new Win32SystemReboot();
        ResidueCleaner = new Win32ResidueCleaner(logger);
        Connectivity = new WindowsConnectivityProbe();
        DmaSetup = new Win32DmaSetupRegion();
        AssetDownload = new GitHubAssetDownload();
    }

    public IWinlogonRegistry Winlogon { get; }

    public IRegionSnapshot Region { get; }

    public IProcessHost Processes { get; }

    public ICheckpointStore Checkpoints { get; }

    public IAppxPackageManager? Appx { get; }

    public ISystemReboot? Reboot { get; }

    public IResidueCleaner? ResidueCleaner { get; }

    public IConnectivityProbe? Connectivity { get; }

    public IDmaSetupRegion? DmaSetup { get; }

    public IAssetDownload? AssetDownload { get; }

    public Func<string?>? ResolveScoopCmd => TryResolveScoopShim;

    public bool IsWslPlatformReady() =>
        OperatingSystem.IsWindows() && Win32WslPlatform.IsVirtualMachinePlatformReady();

    public bool IsWslDistroRegistered(string installId) =>
        OperatingSystem.IsWindows() && Win32WslPlatform.IsDistroRegistered(installId);

    public bool IsHypervisorGuest() =>
        OperatingSystem.IsWindows() && Win32HypervisorGuest.Probe();

    public void ApplyWorkstationQuiet() => Win32WorkstationQuiet.Apply();

    public bool ApplyShellChrome(ShellChromeRequest request) =>
        OperatingSystem.IsWindows() && Win32ShellChrome.Apply(request);

    public void TryStageWslTerminalMock(IReadOnlyList<string> distroNames)
    {
        if (OperatingSystem.IsWindows())
        {
            Win32WslTerminalMock.TryStage(distroNames);
        }
    }

    public void SuppressWslOobe()
    {
        if (OperatingSystem.IsWindows())
        {
            Win32WslPlatform.SuppressDistroOobe();
        }
    }

    public void TryDismissOobeOverlay()
    {
        if (OperatingSystem.IsWindows())
        {
            Win32OobeOverlay.TryDismiss();
        }
    }

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
