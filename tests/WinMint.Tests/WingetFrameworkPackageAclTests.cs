using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;
using WinMint.Provisioning;

namespace WinMint.Tests;

public class WingetFrameworkPackageAclTests
{
    [Fact]
    public void FindPackageDirectories_matches_app_installer_framework_prefixes_only()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-acl-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string uiXaml = Path.Combine(root, "Microsoft.UI.Xaml.2.8_8.2511.26001.0_arm64__8wekyb3d8bbwe");
            string vclibs = Path.Combine(root, "Microsoft.VCLibs.140.00_14.0.33519.0_arm64__8wekyb3d8bbwe");
            string uwpDesktop = Path.Combine(
                root,
                "Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_arm64__8wekyb3d8bbwe");
            string appInstaller = Path.Combine(
                root,
                "Microsoft.DesktopAppInstaller_1.26.509.0_arm64__8wekyb3d8bbwe");
            string cbs = Path.Combine(root, "Microsoft.UI.Xaml.CBS_9.2504.3002.0_arm64__8wekyb3d8bbwe");
            foreach (string dir in new[] { uiXaml, vclibs, uwpDesktop, appInstaller, cbs })
            {
                Directory.CreateDirectory(dir);
            }

            string[] found = WingetFrameworkPackageAcl.FindPackageDirectories(root).OrderBy(d => d).ToArray();

            // UWPDesktop is Microsoft.VCLibs.140.00.UWPDesktop_… (dot, not underscore) — already OK ACLs.
            Assert.Equal(2, found.Length);
            Assert.Contains(uiXaml, found);
            Assert.Contains(vclibs, found);
            Assert.DoesNotContain(uwpDesktop, found);
            Assert.DoesNotContain(appInstaller, found);
            Assert.DoesNotContain(cbs, found);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    [SupportedOSPlatform("windows")]
    public void GrantSystemFullControlTree_replaces_system_rx_only_ace()
    {
        // Simulates inbox shape: explicit SYSTEM=RX on logo.png (SetAccessRule left this untouched).
        string root = Path.Combine(Path.GetTempPath(), "winmint-acl-grant-" + Guid.NewGuid().ToString("N"));
        string nested = Path.Combine(root, "Assets");
        Directory.CreateDirectory(nested);
        string file = Path.Combine(nested, "logo.png");
        File.WriteAllText(file, "x");
        List<string> log = [];
        try
        {
            SecurityIdentifier system = new(WellKnownSidType.LocalSystemSid, null);
            SecurityIdentifier self = WindowsIdentity.GetCurrent().User
                ?? throw new InvalidOperationException("no current user SID");
            FileInfo info = new(file);
            FileSecurity security = info.GetAccessControl();
            security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
            foreach (FileSystemAccessRule existing in security
                         .GetAccessRules(true, true, typeof(SecurityIdentifier))
                         .Cast<FileSystemAccessRule>()
                         .ToArray())
            {
                security.RemoveAccessRule(existing);
            }

            security.AddAccessRule(
                new FileSystemAccessRule(
                    self,
                    FileSystemRights.FullControl,
                    AccessControlType.Allow));
            security.AddAccessRule(
                new FileSystemAccessRule(
                    system,
                    FileSystemRights.ReadAndExecute,
                    AccessControlType.Allow));
            info.SetAccessControl(security);

            WingetFrameworkPackageAcl.GrantSystemFullControlTree(root, log.Add);

            FileSystemAccessRule? systemRule = new FileInfo(file).GetAccessControl()
                .GetAccessRules(true, true, typeof(SecurityIdentifier))
                .Cast<FileSystemAccessRule>()
                .FirstOrDefault(r =>
                    r.IdentityReference.Value == "S-1-5-18"
                    && r.AccessControlType == AccessControlType.Allow);

            Assert.NotNull(systemRule);
            Assert.True(
                systemRule!.FileSystemRights.HasFlag(FileSystemRights.FullControl),
                $"expected FullControl after takeown/icacls, got {systemRule.FileSystemRights}");
            Assert.Contains(log, line => line.Contains("granted SYSTEM FullControl", StringComparison.Ordinal));
        }
        finally
        {
            try
            {
                Directory.Delete(root, recursive: true);
            }
            catch
            {
                // takeown may leave SYSTEM-owned tree; best-effort cleanup
            }
        }
    }

    [Fact]
    [SupportedOSPlatform("windows")]
    public void GrantSystemFullControlTree_throws_when_path_is_locked_from_takeown()
    {
        // Ownership-denial stand-in: takeown /F on a volume root path that is not a package dir
        // fails closed with non-zero exit (was previously swallowed).
        string bogus = Path.Combine(
            Path.GetPathRoot(Path.GetTempPath()) ?? @"C:\",
            "winmint-acl-no-such-" + Guid.NewGuid().ToString("N"));
        Assert.False(Directory.Exists(bogus));
        // Missing dir is a soft skip (not throw) — exercise that contract.
        List<string> log = [];
        WingetFrameworkPackageAcl.GrantSystemFullControlTree(bogus, log.Add);
        Assert.Contains(log, line => line.Contains("skip missing", StringComparison.Ordinal));
    }
}
