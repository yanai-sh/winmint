using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;

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

    public static void GrantSystemFullControlTree(string packageDirectory)
    {
        SecurityIdentifier system = new(WellKnownSidType.LocalSystemSid, null);
        FileSystemAccessRule rule = new(
            system,
            FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
            PropagationFlags.None,
            AccessControlType.Allow);

        ApplyRule(new DirectoryInfo(packageDirectory), rule);
        foreach (string path in Directory.EnumerateFileSystemEntries(
                     packageDirectory,
                     "*",
                     SearchOption.AllDirectories))
        {
            try
            {
                if (Directory.Exists(path))
                {
                    ApplyRule(new DirectoryInfo(path), rule);
                }
                else
                {
                    ApplyRule(new FileInfo(path), rule);
                }
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or SystemException)
            {
                // ponytail: best-effort per entry; one locked file must not abort the tree
            }
        }
    }

    private static void ApplyRule(FileSystemInfo info, FileSystemAccessRule rule)
    {
        if (info is DirectoryInfo dir)
        {
            DirectorySecurity security = dir.GetAccessControl();
            security.SetAccessRule(rule);
            dir.SetAccessControl(security);
            return;
        }

        FileSecurity fileSecurity = ((FileInfo)info).GetAccessControl();
        fileSecurity.SetAccessRule(rule);
        ((FileInfo)info).SetAccessControl(fileSecurity);
    }
}
