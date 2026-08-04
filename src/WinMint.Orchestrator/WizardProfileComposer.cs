using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>
/// Host helper: compose <c>winmint.profile/v1</c> UTF-8 JSON from UI/CLI fields + an already-expanded remove-list.
/// Does not embed preset names (KEEPFLAG: none in Profile).
/// </summary>
public static class WizardProfileComposer
{
    public static byte[] ToUtf8Json(
        string username,
        string password,
        bool requireWifiDuringOobe,
        bool dmaEnabled,
        string locale,
        int geoId,
        string timeZoneId,
        bool locationServicesEnabled,
        IReadOnlyList<string> removeProvisionedAppx)
    {
        ProfileWireDoc doc = new(
            BuildPlan.ProfileSchemaVersion,
            new AccountWireDoc(
                AccountModeWire.LocalAutoLogon,
                username,
                password,
                requireWifiDuringOobe),
            new DmaWireDoc(
                dmaEnabled,
                new SettleWireDoc(locale, geoId, timeZoneId, locationServicesEnabled)),
            removeProvisionedAppx.Count == 0
                ? null
                : new DebloatWireDoc(removeProvisionedAppx.ToArray()));

        return Encoding.UTF8.GetBytes(
            JsonSerializer.Serialize(doc, WizardProfileJsonContext.Default.ProfileWireDoc));
    }
}

internal sealed record ProfileWireDoc(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("account")] AccountWireDoc Account,
    [property: JsonPropertyName("dma")] DmaWireDoc Dma,
    [property: JsonPropertyName("debloat")] DebloatWireDoc? Debloat);

internal sealed record AccountWireDoc(
    [property: JsonPropertyName("mode")] string Mode,
    [property: JsonPropertyName("username")] string Username,
    [property: JsonPropertyName("password")] string Password,
    [property: JsonPropertyName("requireWifiDuringOobe")] bool RequireWifiDuringOobe);

internal sealed record DmaWireDoc(
    [property: JsonPropertyName("enabled")] bool Enabled,
    [property: JsonPropertyName("settle")] SettleWireDoc Settle);

internal sealed record SettleWireDoc(
    [property: JsonPropertyName("locale")] string Locale,
    [property: JsonPropertyName("geoId")] int GeoId,
    [property: JsonPropertyName("timeZoneId")] string TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool LocationServicesEnabled);

internal sealed record DebloatWireDoc(
    [property: JsonPropertyName("removeProvisionedAppx")] string[] RemoveProvisionedAppx);

[JsonSerializable(typeof(ProfileWireDoc))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class WizardProfileJsonContext : JsonSerializerContext;
