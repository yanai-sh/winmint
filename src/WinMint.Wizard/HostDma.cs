using System.Globalization;

namespace WinMint.Wizard;

/// <summary>Host DMA settle snapshot for Wizard compose (issue 56). Profile stores the result.</summary>
public sealed record HostDmaSnapshot(
    string Locale,
    int GeoId,
    string TimeZoneId,
    bool LocationServicesEnabled);

public static class HostDma
{
    /// <summary>Best-effort read of the machine running Wizard. Falls back to stable English desktop defaults.</summary>
    public static HostDmaSnapshot Capture()
    {
        string locale = CultureInfo.CurrentCulture.Name;
        if (string.IsNullOrWhiteSpace(locale))
        {
            locale = "en-GB";
        }

        int geoId = 242;
        try
        {
            geoId = RegionInfo.CurrentRegion.GeoId;
        }
        catch (Exception)
        {
            // ponytail: host region may be unset in some lab images
        }

        string tz = TimeZoneInfo.Local.Id;
        if (string.IsNullOrWhiteSpace(tz))
        {
            tz = "GMT Standard Time";
        }

        return new HostDmaSnapshot(locale, geoId, tz, LocationServicesEnabled: true);
    }
}
