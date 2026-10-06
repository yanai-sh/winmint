using System.Diagnostics;
using System.Runtime.Versioning;

using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// WSL platform helpers (Microsoft Dev Config semantics): VMP probe, distro list, OOBE suppress.
/// </summary>
[SupportedOSPlatform("windows")]
public static class Win32WslPlatform
{
    /// <summary>Virtual Machine Platform active when vmcompute service is registered.</summary>
    public static bool IsVirtualMachinePlatformReady()
    {
        try
        {
            ProcessExitStatus status = Process.Run(
                "sc.exe",
                ["query", "vmcompute"],
                silent: true,
                timeout: TimeSpan.FromSeconds(15));
            return status.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Suppress WSL distro first-run GUI (Microsoft Dev Config InstallUbuntu).</summary>
    public static void SuppressDistroOobe()
    {
        try
        {
            using RegistryKey? lxss = Registry.CurrentUser.CreateSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Lxss");
            lxss?.SetValue("OOBEComplete", 1, RegistryValueKind.DWord);
        }
        catch
        {
            // Best-effort — install still proceeds.
        }
    }

    public static bool IsRebootRequiredExitCode(int exitCode) =>
        exitCode is 3010 or 1641;

    /// <summary>True when <paramref name="installId"/> appears in <c>wsl -l -q</c> output.</summary>
    internal static bool DistroListContainsInstallId(string listOutput, string installId)
    {
        if (string.IsNullOrWhiteSpace(installId) || string.IsNullOrEmpty(listOutput))
        {
            return false;
        }

        foreach (string rawLine in listOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            string line = rawLine.TrimStart('*', ' ', '\0');
            if (line.Equals(installId, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>Registered distro probe for store install verify (Lxss DistributionName).</summary>
    public static bool IsDistroRegistered(string installId)
    {
        if (string.IsNullOrWhiteSpace(installId))
        {
            return false;
        }

        try
        {
            using RegistryKey? lxss = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Lxss");
            if (lxss is null)
            {
                return false;
            }

            foreach (string subKeyName in lxss.GetSubKeyNames())
            {
                if (subKeyName is "PolicyVersion" or "NatIpAddress" or "NatGatewayIpAddress")
                {
                    continue;
                }

                using RegistryKey? distroKey = lxss.OpenSubKey(subKeyName);
                if (distroKey?.GetValue("DistributionName") is string name
                    && name.Equals(installId, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return false;
        }
        catch
        {
            return false;
        }
    }
}
