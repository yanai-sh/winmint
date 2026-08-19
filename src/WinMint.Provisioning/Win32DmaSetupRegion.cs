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
    private static int? ReadDeviceRegion()
    {
        using RegistryKey? key = Registry.LocalMachine.OpenSubKey(DmaInterop.DeviceRegionSubKey, writable: false);
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
            // ponytail: SetupComplete races OOBE still holding DeviceRegion (Unauthorized).
            // 8×250ms lost on 25H2; 30×1s is still shorter than OOBE's hold. Machine-setup
            // fail-opens Unauthorized so SetupComplete can exit 0; settle retries.
            const int tries = 30;
            for (int i = 0; ; i++)
            {
                try
                {
                    WriteDeviceRegion(DmaInterop.IrelandGeoId);
                    break;
                }
                catch (Exception ex) when (
                    ex is UnauthorizedAccessException or SecurityException
                    && i < tries - 1)
                {
                    Thread.Sleep(1000);
                }
            }
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
        using RegistryKey key = Registry.LocalMachine.CreateSubKey(DmaInterop.DeviceRegionSubKey, writable: true)
            ?? throw new InvalidOperationException($"Cannot open HKLM\\{DmaInterop.DeviceRegionSubKey}.");
        key.SetValue("DeviceRegion", geoId, RegistryValueKind.DWord);
    }

    private static void SeedDefaultUserGeo(int geoId, string geoName)
    {
        using RegistryKey key = Registry.Users.CreateSubKey(DmaInterop.DefaultUserGeoSubKey, writable: true)
            ?? throw new InvalidOperationException($@"Cannot open HKU\{DmaInterop.DefaultUserGeoSubKey}.");
        key.SetValue("Nation", geoId.ToString(CultureInfo.InvariantCulture), RegistryValueKind.String);
        key.SetValue("Name", geoName, RegistryValueKind.String);
    }
}
