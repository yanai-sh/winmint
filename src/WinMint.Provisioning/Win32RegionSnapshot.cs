using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security;

using Microsoft.Win32;

using Windows.Win32;
using Windows.Win32.Globalization;

using WinMint.Contracts;

namespace WinMint.Provisioning;

/// <summary>
/// Restores visible region via Win32 NLS / Geo / time zone + location-services consent registry.
/// </summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class Win32RegionSnapshot : IRegionSnapshot
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

        SetUserLocaleName(target.Locale);

        if (!PInvoke.SetUserGeoID(target.GeoId.Value))
        {
            throw new InvalidOperationException(
                $"SetUserGeoID({target.GeoId.Value}) failed: {Marshal.GetLastPInvokeError()}");
        }

        if (!TrySetTimeZone(target.TimeZoneId))
        {
            throw new InvalidOperationException($"Set time zone '{target.TimeZoneId}' failed.");
        }

        // Soft field: Shell is medium-IL; HKLM ConsentStore may deny. Settle poll emits location_warn.
        try
        {
            SetLocationServices(target.LocationServicesEnabled.Value);
        }
        catch (UnauthorizedAccessException)
        {
            // ponytail: location is soft; MachineSetup may pre-stamp or Users ACL grants later
        }
        catch (SecurityException)
        {
            // RegistrySecurity path
        }
    }

    public RegionState Read()
    {
        string? locale = GetUserDefaultLocaleName();
        int geoId = PInvoke.GetUserGeoID(SYSGEOCLASS.GEOCLASS_NATION);
        string? tz = TimeZoneInfo.Local.Id;
        bool? location = ReadLocationServices();
        return new RegionState(locale, geoId, tz, location);
    }

    /// <summary>
    /// There is no <c>SetUserDefaultLocaleName</c> export (only Get*). Inbox
    /// <c>Set-Culture</c> (Windows PowerShell International module) is the supported setter —
    /// same role as <c>tzutil</c> for time zones. Not guest pwsh Core.
    /// </summary>
    public static void SetUserLocaleName(string localeName)
    {
        CultureInfo culture = CultureInfo.GetCultureInfo(localeName);
        string powershell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(powershell))
        {
            throw new InvalidOperationException($"Windows PowerShell missing: {powershell}");
        }

        // Escape single quotes for -Command '…'
        // Sync Process.Run: IRegionSnapshot.Apply is sync (settle fail-open); cancel between probes only.
        string escaped = culture.Name.Replace("'", "''", StringComparison.Ordinal);
        ProcessExitStatus status = Process.Run(
            powershell,
            [
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                $"Set-Culture -CultureInfo '{escaped}'",
            ],
            silent: true,
            timeout: TimeSpan.FromSeconds(60));

        if (status.Canceled)
        {
            throw new InvalidOperationException($"Set-Culture '{culture.Name}' timed out.");
        }

        if (status.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"Set-Culture '{culture.Name}' exited {status.ExitCode}.");
        }

        string? read = GetUserDefaultLocaleName();
        if (!string.Equals(read, culture.Name, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"User locale apply verify failed: Set-Culture '{culture.Name}', GetUserDefaultLocaleName returned '{read}'.");
        }
    }

    private static string? GetUserDefaultLocaleName()
    {
        Span<char> buffer = stackalloc char[85];
        int written = PInvoke.GetUserDefaultLocaleName(buffer);
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
        // Sync Process.Run: same sync Apply contract as Set-Culture (see SetUserLocaleName).
        string tzutil = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "tzutil.exe");
        if (!File.Exists(tzutil))
        {
            return false;
        }

        ProcessExitStatus status = Process.Run(
            tzutil,
            ["/s", timeZoneId],
            silent: true,
            timeout: TimeSpan.FromSeconds(30));

        if (status.Canceled || status.ExitCode != 0)
        {
            return false;
        }

        // BCL caches TimeZoneInfo.Local — flush so the next Read() sees the new zone.
        TimeZoneInfo.ClearCachedData();
        return true;
    }
}
