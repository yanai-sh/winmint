using System.Globalization;

namespace WinMint.Wizard;

/// <summary>Host DMA settle snapshot for Wizard compose (issue 56). Profile stores the result.</summary>
public sealed record BuildMachineDmaSnapshot(
    string Locale,
    int GeoId,
    string TimeZoneId,
    bool LocationServicesEnabled);

public static class BuildMachineDma
{
    /// <summary>Best-effort read of the machine running Wizard. Falls back to stable English desktop defaults.</summary>
    public static BuildMachineDmaSnapshot Capture()
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

        return new BuildMachineDmaSnapshot(locale, geoId, tz, LocationServicesEnabled: true);
    }
}
