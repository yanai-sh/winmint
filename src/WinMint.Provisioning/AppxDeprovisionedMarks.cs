using System.Runtime.Versioning;

using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// Live HKLM Deprovisioned marks — same FU-survival semantics as offline Remove-ProvisionedAppx.ps1.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class AppxDeprovisionedMarks
{
    public const string DeprovisionedRoot =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned";

    /// <summary>Create <c>Deprovisioned\&lt;PFN&gt;</c> if missing. Returns false on access failure.</summary>
    public static bool Ensure(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        try
        {
            using RegistryKey? root = Registry.LocalMachine.CreateSubKey(
                Path.Combine(DeprovisionedRoot, packageFamilyName),
                writable: true);
            return root is not null;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>True when the Deprovisioned PFN key already exists.</summary>
    public static bool Exists(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        try
        {
            using RegistryKey? key = Registry.LocalMachine.OpenSubKey(
                Path.Combine(DeprovisionedRoot, packageFamilyName),
                writable: false);
            return key is not null;
        }
        catch
        {
            return false;
        }
    }
}
