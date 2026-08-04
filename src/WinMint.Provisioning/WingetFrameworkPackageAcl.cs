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
    /// </summary>
    public static void GrantSystemFullControlTree(string packageDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageDirectory);
        if (!Directory.Exists(packageDirectory))
        {
            return;
        }

        // SetupComplete is SYSTEM; takeown still needed so icacls can replace TrustedInstaller ACEs.
        RunHidden("takeown.exe", $"/F \"{packageDirectory}\" /R /D Y");
        RunHidden(
            "icacls.exe",
            $"\"{packageDirectory}\" /grant:r \"NT AUTHORITY\\SYSTEM:(OI)(CI)(F)\" /T /C");
    }

    private static void RunHidden(string fileName, string arguments)
    {
        using Process process = new()
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
        };
        process.Start();
        // Drain so the child cannot block on full pipes.
        _ = process.StandardOutput.ReadToEnd();
        _ = process.StandardError.ReadToEnd();
        if (!process.WaitForExit(120_000))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
                // ponytail: best-effort kill on ACL helper hang
            }
        }
    }
}
