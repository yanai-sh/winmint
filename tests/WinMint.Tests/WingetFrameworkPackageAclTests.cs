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
    public void GrantSystemFullControlTree_sets_local_system_full_control()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-acl-grant-" + Guid.NewGuid().ToString("N"));
        string nested = Path.Combine(root, "Assets");
        Directory.CreateDirectory(nested);
        string file = Path.Combine(nested, "logo.png");
        File.WriteAllText(file, "x");
        try
        {
            WingetFrameworkPackageAcl.GrantSystemFullControlTree(root);

            FileInfo info = new(file);
            FileSystemAccessRule? systemRule = info.GetAccessControl()
                .GetAccessRules(true, true, typeof(SecurityIdentifier))
                .Cast<FileSystemAccessRule>()
                .FirstOrDefault(r =>
                    r.IdentityReference.Value == "S-1-5-18"
                    && r.AccessControlType == AccessControlType.Allow);

            Assert.NotNull(systemRule);
            Assert.True(
                systemRule!.FileSystemRights.HasFlag(FileSystemRights.FullControl)
                || systemRule.FileSystemRights.HasFlag(FileSystemRights.WriteData));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
