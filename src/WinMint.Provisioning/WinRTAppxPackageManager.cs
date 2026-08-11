using System.Diagnostics;
using System.Runtime.Versioning;
using System.Security.Principal;
using Microsoft.Extensions.Logging;
using Windows.ApplicationModel;
using Windows.Management.Deployment;

namespace WinMint.Provisioning;

/// <summary>Production PackageManager adapter for FirstLogon AppX safety net (ticket 13).</summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class WinRTAppxPackageManager(ILogger? logger = null) : IAppxPackageManager
{
    private readonly PackageManager _manager = new();
    private readonly ILogger? _logger = logger;

    private static string WindowsAppsRoot =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "WindowsApps");

    /// <summary>WindowsApps directory name prefixes for App Installer framework deps.</summary>
    private static readonly string[] WingetFrameworkDirectoryPrefixes =
    [
        "Microsoft.UI.Xaml.2.8_",
        "Microsoft.VCLibs.140.00_",
    ];

    public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogId);
        List<AppxPackageInfo> hits = [];
        try
        {
            foreach (Package package in _manager.FindPackagesForUser(string.Empty))
            {
                AppxPackageInfo info = ToInfo(package);
                if (MatchesCatalogId(info, catalogId))
                {
                    hits.Add(info);
                }
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // ponytail: medium-IL FirstLogon — access-denied ⇒ empty hits (offline DISM owns provisioned)
            return [];
        }

        return hits.ToArray();
    }

    public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogId);
        List<AppxPackageInfo> hits = [];
        try
        {
            foreach (Package package in _manager.FindProvisionedPackages())
            {
                AppxPackageInfo info = ToInfo(package);
                if (MatchesCatalogId(info, catalogId))
                {
                    hits.Add(info);
                }
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // ponytail: FindProvisionedPackages needs elevation; offline remove already handled provisioned
            return [];
        }

        return hits.ToArray();
    }

    public async Task RemovePackageAsync(string packageFullName, CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFullName);
        try
        {
            DeploymentResult result = await _manager.RemovePackageAsync(packageFullName).AsTask(ct)
                .ConfigureAwait(false);
            if (!string.IsNullOrEmpty(result.ErrorText))
            {
                throw new InvalidOperationException($"RemovePackageAsync({packageFullName}): {result.ErrorText}");
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // ponytail: medium-IL remove fail-open — leave registered package for elevated pass
        }
    }

    public async Task DeprovisionPackageFamilyAsync(string packageFamilyName, CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        try
        {
            DeploymentResult result = await _manager
                .DeprovisionPackageForAllUsersAsync(packageFamilyName)
                .AsTask(ct)
                .ConfigureAwait(false);
            if (!string.IsNullOrEmpty(result.ErrorText))
            {
                throw new InvalidOperationException(
                    $"DeprovisionPackageForAllUsersAsync({packageFamilyName}): {result.ErrorText}");
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // ponytail: DeprovisionPackageForAllUsers needs admin; offline DISM path owns this
        }
    }

    public void EnsureDeprovisionedMark(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        if (AppxDeprovisionedMarks.Exists(packageFamilyName))
        {
            return;
        }

        _ = AppxDeprovisionedMarks.Ensure(packageFamilyName);
    }

    public async Task RegisterPackageFamilyForCurrentUserAsync(
        string packageFamilyName,
        CancellationToken ct = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);

        // CsWinRT: null IIterable args — string[] fails CCW cast (IID IIterable<HSTRING>).
        DeploymentResult result = await _manager.RegisterPackageByFamilyNameAsync(
                packageFamilyName,
                dependencyPackageFamilyNames: null,
                DeploymentOptions.None,
                appDataVolume: null,
                optionalPackageFamilyNames: null)
            .AsTask(ct)
            .ConfigureAwait(false);
        if (!string.IsNullOrEmpty(result.ErrorText))
        {
            throw new InvalidOperationException(
                $"RegisterPackageByFamilyNameAsync({packageFamilyName}): {result.ErrorText}");
        }
    }

    public void EnsureSystemFullControlOnWingetFrameworkPackages()
    {
        // FirstLogon Shell is medium-IL — cannot takeown TrustedInstaller WindowsApps trees.
        if (!WindowsIdentity.GetCurrent().IsSystem)
        {
            if (_logger is not null)
            {
                GuestLog.WingetAclSkip(_logger);
            }

            return;
        }

        string root = WindowsAppsRoot;
        string[] dirs = FindWingetFrameworkPackageDirectories(root).ToArray();
        if (_logger is not null)
        {
            GuestLog.WingetAclFound(_logger, dirs.Length, root);
        }

        if (dirs.Length == 0)
        {
            if (_logger is not null)
            {
                GuestLog.WingetAclNoneMatched(_logger);
            }

            return;
        }

        foreach (string dir in dirs)
        {
            try
            {
                GrantSystemFullControlTree(dir, _logger);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or SystemException)
            {
                // Breadcrumb only — MachineSetup must not fail closed; FirstLogon register surfaces fail.
                if (_logger is not null)
                {
                    GuestLog.WingetAclFailed(_logger, dir, ex.Message);
                }
            }
        }
    }

    private static IEnumerable<string> FindWingetFrameworkPackageDirectories(string windowsAppsRoot)
    {
        if (!Directory.Exists(windowsAppsRoot))
        {
            yield break;
        }

        foreach (string dir in Directory.EnumerateDirectories(windowsAppsRoot))
        {
            string name = Path.GetFileName(dir);
            if (WingetFrameworkDirectoryPrefixes.Any(prefix =>
                    name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
            {
                yield return dir;
            }
        }
    }

    /// <summary>
    /// takeown + icacls /grant:r — .NET SetAccessRule leaves explicit SYSTEM=RX ACEs (logo.png) untouched.
    /// Throws when either tool exits non-zero (caller logs; MachineSetup stays best-effort).
    /// </summary>
    private static void GrantSystemFullControlTree(string packageDirectory, ILogger? logger = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageDirectory);
        if (!Directory.Exists(packageDirectory))
        {
            if (logger is not null)
            {
                GuestLog.WingetAclSkipMissing(logger, packageDirectory);
            }

            return;
        }

        string system32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string takeown = Path.Combine(system32, "takeown.exe");
        string icacls = Path.Combine(system32, "icacls.exe");

        // SetupComplete is SYSTEM; takeown still needed so icacls can replace TrustedInstaller ACEs.
        // (F) + /T — not (OI)(CI)(F): inherit-only grants leave explicit SYSTEM=RX on files (logo.png).
        // Sync Process.Run: EnsureSystemFullControl is a sync MachineSetup port; cancel is fail-open via catch.
        RunAclTool(takeown, ["/F", packageDirectory, "/R", "/D", "Y"], logger);
        RunAclTool(
            icacls,
            [packageDirectory, "/grant:r", @"NT AUTHORITY\SYSTEM:(F)", "/T", "/C", "/Q"],
            logger);
        if (logger is not null)
        {
            GuestLog.WingetAclGranted(logger, packageDirectory);
        }
    }

    private static void RunAclTool(
        string fileName,
        IReadOnlyList<string> arguments,
        ILogger? logger)
    {
        if (!File.Exists(fileName))
        {
            throw new InvalidOperationException($"ACL helper missing: {fileName}");
        }

        // silent → null stdin/stdout/stderr (no pipe flood / deadlock from recursive takeown).
        ProcessExitStatus status = Process.Run(
            fileName,
            arguments as IList<string> ?? [.. arguments],
            silent: true,
            timeout: TimeSpan.FromSeconds(180));

        if (status.Canceled)
        {
            throw new TimeoutException($"{Path.GetFileName(fileName)} timed out on {arguments[0]}");
        }

        if (status.ExitCode != 0)
        {
            string detail =
                $"{Path.GetFileName(fileName)} exit {status.ExitCode} args=[{string.Join(' ', arguments)}]";
            if (logger is not null)
            {
                GuestLog.WingetAclFailed(logger, detail, string.Empty);
            }

            throw new InvalidOperationException(detail);
        }
    }

    public string? TryResolveWingetExecutablePath()
    {
        try
        {
            foreach (Package package in _manager.FindPackagesForUser(
                         string.Empty,
                         ProvisioningSession.DesktopAppInstallerFamilyName))
            {
                string candidate = Path.Combine(package.InstalledLocation.Path, "winget.exe");
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex) || ex is IOException)
        {
            return null;
        }

        return null;
    }

    private static bool IsAccessDenied(Exception ex)
    {
        for (Exception? e = ex; e is not null; e = e.InnerException)
        {
            if (e is UnauthorizedAccessException)
            {
                return true;
            }

            if (e.Message.Contains("Access is denied", StringComparison.OrdinalIgnoreCase)
                || e.Message.Contains("0x80070005", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static AppxPackageInfo ToInfo(Package package) =>
        new(
            package.Id.FullName,
            package.Id.FamilyName,
            string.IsNullOrWhiteSpace(package.Id.Name) ? package.DisplayName : package.Id.Name);

    internal static bool MatchesCatalogId(AppxPackageInfo package, string catalogId) =>
        string.Equals(package.DisplayName, catalogId, StringComparison.OrdinalIgnoreCase)
        || package.PackageFamilyName.StartsWith(catalogId + "_", StringComparison.OrdinalIgnoreCase)
        || package.PackageFullName.StartsWith(catalogId + "_", StringComparison.OrdinalIgnoreCase);
}
