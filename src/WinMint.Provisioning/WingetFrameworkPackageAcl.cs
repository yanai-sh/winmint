using System.Diagnostics;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

/// <summary>
/// Inbox App Installer frameworks (UI.Xaml.2.8, VCLibs) are often staged with SYSTEM=RX only.
/// RegisterByFamilyName needs SYSTEM write to set Trust Labels — grant FullControl under SetupComplete.
/// </summary>
[SupportedOSPlatform("windows")]
public static class WingetFrameworkPackageAcl
{
    /// <summary>WindowsApps directory name prefixes for App Installer framework deps.</summary>
    public static readonly string[] DirectoryNamePrefixes =
    [
        "Microsoft.UI.Xaml.2.8_",
        "Microsoft.VCLibs.140.00_",
    ];

    public static IEnumerable<string> FindPackageDirectories(string windowsAppsRoot)
    {
        if (!Directory.Exists(windowsAppsRoot))
        {
            yield break;
        }

        foreach (string dir in Directory.EnumerateDirectories(windowsAppsRoot))
        {
            string name = Path.GetFileName(dir);
            if (DirectoryNamePrefixes.Any(prefix =>
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
    public static void GrantSystemFullControlTree(string packageDirectory, Action<string>? log = null)
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
        RunTool(takeown, ["/F", packageDirectory, "/R", "/D", "Y"], log);
        RunTool(
            icacls,
            [packageDirectory, "/grant:r", @"NT AUTHORITY\SYSTEM:(F)", "/T", "/C", "/Q"],
            log);
        log?.Invoke($"winget.acl: granted SYSTEM FullControl on {packageDirectory}");
    }

    private static void RunTool(string fileName, IReadOnlyList<string> arguments, Action<string>? log)
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
}
