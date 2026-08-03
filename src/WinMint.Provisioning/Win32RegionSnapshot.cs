using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// Restores visible region via Win32 NLS / Geo / time zone + location-services consent registry.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed partial class Win32RegionSnapshot : IRegionSnapshot
{
    private const string LocationConsentSubKey =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location";

    public void Apply(DmaSettleTarget target)
    {
        ArgumentNullException.ThrowIfNull(target);
        if (string.IsNullOrWhiteSpace(target.Locale)
            || target.GeoId is null
            || string.IsNullOrWhiteSpace(target.TimeZoneId)
            || target.LocationServicesEnabled is null)
        {
            throw new ArgumentException(
                "DMA settle Apply requires locale, geoId, timeZoneId, and locationServicesEnabled.",
                nameof(target));
        }

        int localeRc = SetUserDefaultLocaleName(target.Locale);
        if (localeRc == 0)
        {
            throw new InvalidOperationException($"SetUserDefaultLocaleName('{target.Locale}') failed.");
        }

        if (!SetUserGeoID(target.GeoId.Value))
        {
            throw new InvalidOperationException($"SetUserGeoID({target.GeoId.Value}) failed.");
        }

        if (!TrySetTimeZone(target.TimeZoneId))
        {
            throw new InvalidOperationException($"Set time zone '{target.TimeZoneId}' failed.");
        }

        SetLocationServices(target.LocationServicesEnabled.Value);
    }

    public RegionState Read()
    {
        string? locale = GetUserDefaultLocaleName();
        int geoId = GetUserGeoID(GEOCLASS_NATION);
        string? tz = TimeZoneInfo.Local.Id;
        bool? location = ReadLocationServices();
        return new RegionState(locale, geoId, tz, location);
    }

    private static string? GetUserDefaultLocaleName()
    {
        Span<char> buffer = stackalloc char[85];
        int written = GetUserDefaultLocaleName(buffer, buffer.Length);
        if (written <= 0)
        {
            return null;
        }

        return buffer[..(written - 1)].ToString(); // drop trailing null
    }

    private static void SetLocationServices(bool enabled)
    {
        using RegistryKey key = Registry.LocalMachine.CreateSubKey(LocationConsentSubKey, writable: true)
            ?? throw new InvalidOperationException($"Cannot open HKLM\\{LocationConsentSubKey}.");
        // ValueAllow=0x1, ValueDeny=0x0 — same tokens Settings uses for system location.
        key.SetValue("Value", enabled ? "Allow" : "Deny", RegistryValueKind.String);
    }

    private static bool? ReadLocationServices()
    {
        using RegistryKey? key = Registry.LocalMachine.OpenSubKey(LocationConsentSubKey, writable: false);
        if (key?.GetValue("Value") is not string raw)
        {
            return null;
        }

        return raw.Equals("Allow", StringComparison.OrdinalIgnoreCase);
    }

    private static bool TrySetTimeZone(string timeZoneId)
    {
        // ponytail: TZUtil is the supported user-mode setter; P/Invoke DYNAMIC_TIME_ZONE is larger.
        using var process = new System.Diagnostics.Process
        {
            StartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "tzutil.exe"),
                ArgumentList = { "/s", timeZoneId },
                UseShellExecute = false,
                CreateNoWindow = true,
            },
        };
        process.Start();
        if (!process.WaitForExit(30_000))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
                // best-effort; timeout already means Apply failed
            }

            return false;
        }

        if (process.ExitCode != 0)
        {
            return false;
        }

        // BCL caches TimeZoneInfo.Local — flush so the next Read() sees the new zone.
        TimeZoneInfo.ClearCachedData();
        return true;
    }

    private const int GEOCLASS_NATION = 16;

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetUserGeoID(int geoId);

    [LibraryImport("kernel32.dll")]
    private static partial int GetUserGeoID(int geoClass);

    [LibraryImport("kernel32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int SetUserDefaultLocaleName(string localeName);

    [LibraryImport("kernel32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int GetUserDefaultLocaleName(Span<char> localeName, int cchLocaleName);
}
