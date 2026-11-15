using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// Boot generation from the prefetch BootId.
/// A failed read is null. Zero is a real boot id and must not stand in for a failed read.
/// </summary>
internal static class Win32BootTick
{
    private const string BootIdKey =
        @"SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters";

    internal static BootTick? Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        try
        {
            using RegistryKey? key = Registry.LocalMachine.OpenSubKey(BootIdKey);
            if (key?.GetValue("BootId") is not int bootId)
            {
                return null;
            }

            return new BootTick(bootId);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return null;
        }
    }
}
