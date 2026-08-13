using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Contracts;

/// <summary>
/// Guest <c>bundle.json</c> interchange (ImageServicing write / BundleLoader read). One schema constant,
/// one wire record — the writer and the reader must not spell the version twice.
/// </summary>
public static class GuestBundleWire
{
    public const string SchemaVersion = "winmint.provisioning.bundle/v1";

    public static string Write(BundleFile bundle)
    {
        ArgumentNullException.ThrowIfNull(bundle);
        return JsonSerializer.Serialize(bundle, GuestBundleWireJsonContext.Default.BundleFile);
    }

    public static bool TryParse(
        ReadOnlySpan<byte> utf8,
        [NotNullWhen(true)] out BundleFile? file,
        out GuestBundleWireError error)
    {
        try
        {
            file = JsonSerializer.Deserialize(utf8, GuestBundleWireJsonContext.Default.BundleFile);
        }
        catch (JsonException ex)
        {
            file = null;
            error = new GuestBundleWireError("bundle.parse", $"Failed to parse bundle: {ex.Message}");
            return false;
        }

        if (file is null)
        {
            error = new GuestBundleWireError("bundle.parse", "Failed to parse bundle.");
            return false;
        }

        if (!string.Equals(file.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            error = new GuestBundleWireError(
                "bundle.schema",
                $"Unsupported bundle schema '{file.SchemaVersion}' (need {SchemaVersion}).");
            return false;
        }

        error = default;
        return true;
    }
}

public readonly record struct GuestBundleWireError(string Code, string Message);

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

[JsonSerializable(typeof(BundleFile))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class GuestBundleWireJsonContext : JsonSerializerContext;
