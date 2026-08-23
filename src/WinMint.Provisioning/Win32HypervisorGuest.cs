using System.Runtime.Versioning;

using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// Live guest probe. BIOS registry is <c>Win32_ComputerSystem</c> Manufacturer/Model without WMI.
/// </summary>
[SupportedOSPlatform("windows")]
public static class Win32HypervisorGuest
{
    public static bool Probe()
    {
        try
        {
            using RegistryKey? guest = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Virtual Machine\Guest");
            using RegistryKey? bios = Registry.LocalMachine.OpenSubKey(
                @"HARDWARE\DESCRIPTION\System\BIOS");
            string? manufacturer = bios?.GetValue("SystemManufacturer") as string;
            string? model = bios?.GetValue("SystemProductName") as string;
            return HypervisorGuest.IsGuest(manufacturer, model, hyperVGuestKeyExists: guest is not null);
        }
        catch
        {
            return false;
        }
    }
}
