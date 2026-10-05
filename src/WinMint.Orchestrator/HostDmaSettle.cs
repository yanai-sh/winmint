using System.Globalization;

namespace WinMint.Orchestrator;

/// <summary>Host DMA settle snapshot for curated / Wizard compose (issue 56 / #136).</summary>
public sealed record HostDmaSettleSnapshot(
    string Locale,
    int GeoId,
    string TimeZoneId,
    bool LocationServicesEnabled);

public static class HostDmaSettle
{
    /// <summary>Best-effort read of the machine running the host tool. Falls back to stable English desktop defaults.</summary>
    public static HostDmaSettleSnapshot Capture()
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

        return new HostDmaSettleSnapshot(locale, geoId, tz, LocationServicesEnabled: true);
    }
}
