using System.Diagnostics;
using System.Runtime.Versioning;
using System.Security.Principal;
using Windows.ApplicationModel;
using Windows.Management.Deployment;

namespace WinMint.Provisioning;

/// <summary>Production PackageManager adapter for FirstLogon AppX safety net (ticket 13).</summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class WinRTAppxPackageManager : IAppxPackageManager
{
    private readonly PackageManager _manager = new();
    private readonly Action<string>? _log;

    public WinRTAppxPackageManager(Action<string>? log = null) => _log = log;

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
            // Medium-IL Shell: treat as no registered hits
            return [];
        }

        return hits;
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

        return hits;
    }

    public void RemovePackage(string packageFullName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFullName);
        try
        {
            DeploymentResult result = _manager.RemovePackageAsync(packageFullName).AsTask().GetAwaiter().GetResult();
            if (!string.IsNullOrEmpty(result.ErrorText))
            {
                throw new InvalidOperationException($"RemovePackageAsync({packageFullName}): {result.ErrorText}");
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // Medium-IL may not remove; leave registered package for a future elevated pass
        }
    }

    public void DeprovisionPackageFamily(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        try
        {
            DeploymentResult result = _manager
                .DeprovisionPackageForAllUsersAsync(packageFamilyName)
                .AsTask()
                .GetAwaiter()
                .GetResult();
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

    public void RegisterPackageFamilyForCurrentUser(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);

        // CsWinRT: null IIterable args — string[] fails CCW cast (IID IIterable<HSTRING>).
        DeploymentResult result = _manager
            .RegisterPackageByFamilyNameAsync(
                packageFamilyName,
                dependencyPackageFamilyNames: null,
                DeploymentOptions.None,
                appDataVolume: null,
                optionalPackageFamilyNames: null)
            .AsTask()
            .GetAwaiter()
            .GetResult();
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
            _log?.Invoke("winget.acl: skip — not SYSTEM");
            return;
        }

        string root = WindowsAppsRoot;
        string[] dirs = FindWingetFrameworkPackageDirectories(root).ToArray();
        _log?.Invoke($"winget.acl: found {dirs.Length} under {root}");
        if (dirs.Length == 0)
        {
            _log?.Invoke(
                "winget.acl: none matched Microsoft.UI.Xaml.2.8_* / Microsoft.VCLibs.140.00_*");
            return;
        }

        foreach (string dir in dirs)
        {
            try
            {
                GrantSystemFullControlTree(dir, _log);
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or SystemException)
            {
                // Breadcrumb only — MachineSetup must not fail closed; FirstLogon register surfaces fail.
                _log?.Invoke($"winget.acl: FAILED {dir}: {ex.Message}");
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
    private static void GrantSystemFullControlTree(string packageDirectory, Action<string>? log = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageDirectory);
        if (!Directory.Exists(packageDirectory))
        {
            log?.Invoke($"winget.acl: skip missing {packageDirectory}");
            return;
        }

        string system32 = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string takeown = Path.Combine(system32, "takeown.exe");
        string icacls = Path.Combine(system32, "icacls.exe");

        // SetupComplete is SYSTEM; takeown still needed so icacls can replace TrustedInstaller ACEs.
        // (F) + /T — not (OI)(CI)(F): inherit-only grants leave explicit SYSTEM=RX on files (logo.png).
        RunAclTool(takeown, ["/F", packageDirectory, "/R", "/D", "Y"], log);
        RunAclTool(
            icacls,
            [packageDirectory, "/grant:r", @"NT AUTHORITY\SYSTEM:(F)", "/T", "/C", "/Q"],
            log);
        log?.Invoke($"winget.acl: granted SYSTEM FullControl on {packageDirectory}");
    }

    private static void RunAclTool(string fileName, IReadOnlyList<string> arguments, Action<string>? log)
    {
        if (!File.Exists(fileName))
        {
            throw new InvalidOperationException($"ACL helper missing: {fileName}");
        }

        // ponytail: local spawn — Win32ProcessHost is CT/no-timeout; ACL needs 180s + no-redirect (pipe flood)
        using Process process = new()
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                UseShellExecute = false,
                CreateNoWindow = true,
                // ponytail: no redirect — recursive takeown floods pipes and deadlocks ReadToEnd.
            },
        };
        foreach (string arg in arguments)
        {
            process.StartInfo.ArgumentList.Add(arg);
        }

        process.Start();
        if (!process.WaitForExit(180_000))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
                // ponytail: best-effort kill on ACL helper hang
            }

            throw new TimeoutException($"{Path.GetFileName(fileName)} timed out on {arguments[0]}");
        }

        if (process.ExitCode != 0)
        {
            string detail =
                $"{Path.GetFileName(fileName)} exit {process.ExitCode} args=[{string.Join(' ', arguments)}]";
            log?.Invoke($"winget.acl: FAILED {detail}");
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
