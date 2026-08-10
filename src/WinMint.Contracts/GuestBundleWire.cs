using System.Text.Json.Serialization;

namespace WinMint.Contracts;

/// <summary>Guest <c>bundle.json</c> interchange (ImageServicing write / BundleLoader read).</summary>
public sealed record BundleFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("supervisorPath")] string SupervisorPath,
    [property: JsonPropertyName("username")] string Username,
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("dmaEnabled")] bool DmaEnabled,
    [property: JsonPropertyName("settle")] SettleFile? Settle,
    [property: JsonPropertyName("removeProvisionedAppx")] string[]? RemoveProvisionedAppx,
    [property: JsonPropertyName("requiresNetwork")] bool RequiresNetwork = false,
    [property: JsonPropertyName("packageStrict")] bool PackageStrict = false);

/// <summary>Guest settle object inside bundle (no Enabled — that is <c>dmaEnabled</c> on the bundle).</summary>
public sealed record SettleFile(
    [property: JsonPropertyName("locale")] string Locale,
    [property: JsonPropertyName("geoId")] int GeoId,
    [property: JsonPropertyName("timeZoneId")] string TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool LocationServicesEnabled);
