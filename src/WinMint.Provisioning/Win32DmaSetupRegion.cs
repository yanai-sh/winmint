using System.Globalization;
using System.Runtime.Versioning;
using System.Security;
using Microsoft.Win32;
using WinMint.Contracts;

namespace WinMint.Provisioning;

/// <summary>
/// Sticky DMA setup region via <c>DeviceRegion</c> (+ seed <c>.DEFAULT</c> Geo for first-cache races).
/// </summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class Win32DmaSetupRegion : IDmaSetupRegion
{
    private const string DeviceRegionSubKey =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion";

    /// <summary>Relative to HKU — a leading backslash is ERROR_BAD_PATHNAME, not a root marker.</summary>
    private const string DefaultUserGeoSubKey =
        @".DEFAULT\Control Panel\International\Geo";

    private static int? ReadDeviceRegion()
    {
        using RegistryKey? key = Registry.LocalMachine.OpenSubKey(DeviceRegionSubKey, writable: false);
        object? raw = key?.GetValue("DeviceRegion");
        return raw switch
        {
            int i => i,
            long l when l is >= int.MinValue and <= int.MaxValue => (int)l,
            _ => null,
        };
    }

    public DmaSetupRegionEnsureResult EnsureIreland()
    {
        int? current = ReadDeviceRegion();
        bool alreadyOk = current == DmaInterop.IrelandGeoId;
        if (!alreadyOk)
        {
            WriteDeviceRegion(DmaInterop.IrelandGeoId);
        }

        // Seed .DEFAULT so first GetUserGeoID fallback cannot race before DeviceRegion is read.
        try
        {
            SeedDefaultUserGeo(DmaInterop.IrelandGeoId, DmaInterop.IrelandGeoName);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or SecurityException or IOException)
        {
            // ponytail: DeviceRegion is authoritative; .DEFAULT seed is belt-and-suspenders.
            // A medium-IL Shell hitting HKU\.DEFAULT raises IOException, not just access denied.
        }

        int? verified = ReadDeviceRegion();
        if (verified != DmaInterop.IrelandGeoId)
        {
            throw new InvalidOperationException(
                $"DeviceRegion verify failed: expected {DmaInterop.IrelandGeoId}, got '{verified?.ToString(CultureInfo.InvariantCulture) ?? "<null>"}'.");
        }

        return alreadyOk ? DmaSetupRegionEnsureResult.AlreadyOk : DmaSetupRegionEnsureResult.Repaired;
    }

    private static void WriteDeviceRegion(int geoId)
    {
        using RegistryKey key = Registry.LocalMachine.CreateSubKey(DeviceRegionSubKey, writable: true)
            ?? throw new InvalidOperationException($"Cannot open HKLM\\{DeviceRegionSubKey}.");
        key.SetValue("DeviceRegion", geoId, RegistryValueKind.DWord);
    }

    private static void SeedDefaultUserGeo(int geoId, string geoName)
    {
        using RegistryKey key = Registry.Users.CreateSubKey(DefaultUserGeoSubKey, writable: true)
            ?? throw new InvalidOperationException($@"Cannot open HKU\{DefaultUserGeoSubKey}.");
        key.SetValue("Nation", geoId.ToString(CultureInfo.InvariantCulture), RegistryValueKind.String);
        key.SetValue("Name", geoName, RegistryValueKind.String);
    }
}
