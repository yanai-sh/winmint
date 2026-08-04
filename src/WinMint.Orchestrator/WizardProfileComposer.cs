using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>
/// Host helper: compose <c>winmint.profile/v1</c> UTF-8 JSON from UI/CLI fields + already-expanded debloat lists.
/// Does not embed preset names (KEEPFLAG: none in Profile). Package ids (when present) live in Profile JSON.
/// </summary>
public static class WizardProfileComposer
{
    /// <summary>Newline-separated package ids: trim lines, drop blanks, preserve order.</summary>
    public static IReadOnlyList<string> ParseIdList(string? multiline)
    {
        if (string.IsNullOrWhiteSpace(multiline))
        {
            return [];
        }

        List<string> ids = [];
        foreach (string line in multiline.Split(['\r', '\n'], StringSplitOptions.None))
        {
            string id = line.Trim();
            if (id.Length > 0)
            {
                ids.Add(id);
            }
        }

        return ids;
    }

    public static byte[] ToUtf8Json(
        string username,
        string password,
        bool requireWifiDuringOobe,
        bool dmaEnabled,
        string locale,
        int geoId,
        string timeZoneId,
        bool locationServicesEnabled,
        IReadOnlyList<string> removeProvisionedAppx,
        IReadOnlyList<string>? winget = null,
        IReadOnlyList<string>? wingetNeedsReboot = null,
        IReadOnlyList<string>? scoop = null,
        IReadOnlyList<string>? scoopNeedsReboot = null,
        IReadOnlyList<string>? wsl = null,
        IReadOnlyList<string>? wslNeedsReboot = null,
        IReadOnlyList<string>? removeCapabilities = null,
        IReadOnlyList<string>? disableOptionalFeatures = null)
    {
        winget ??= [];
        wingetNeedsReboot ??= [];
        scoop ??= [];
        scoopNeedsReboot ??= [];
        wsl ??= [];
        wslNeedsReboot ??= [];
        removeCapabilities ??= [];
        disableOptionalFeatures ??= [];

        PackagesWireDoc? packages = null;
        if (winget.Count > 0 || wingetNeedsReboot.Count > 0
            || scoop.Count > 0 || scoopNeedsReboot.Count > 0
            || wsl.Count > 0 || wslNeedsReboot.Count > 0)
        {
            packages = new PackagesWireDoc(
                winget.Count == 0 ? null : winget.ToArray(),
                wingetNeedsReboot.Count == 0 ? null : wingetNeedsReboot.ToArray(),
                scoop.Count == 0 ? null : scoop.ToArray(),
                scoopNeedsReboot.Count == 0 ? null : scoopNeedsReboot.ToArray(),
                wsl.Count == 0 ? null : wsl.ToArray(),
                wslNeedsReboot.Count == 0 ? null : wslNeedsReboot.ToArray());
        }

        DebloatWireDoc? debloat = null;
        if (removeProvisionedAppx.Count > 0 || removeCapabilities.Count > 0 || disableOptionalFeatures.Count > 0)
        {
            debloat = new DebloatWireDoc(
                removeProvisionedAppx.Count == 0 ? null : removeProvisionedAppx.ToArray(),
                removeCapabilities.Count == 0 ? null : removeCapabilities.ToArray(),
                disableOptionalFeatures.Count == 0 ? null : disableOptionalFeatures.ToArray());
        }

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
            debloat,
            packages);

        return Encoding.UTF8.GetBytes(
            JsonSerializer.Serialize(doc, WizardProfileJsonContext.Default.ProfileWireDoc));
    }
}

internal sealed record ProfileWireDoc(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("account")] AccountWireDoc Account,
    [property: JsonPropertyName("dma")] DmaWireDoc Dma,
    [property: JsonPropertyName("debloat")] DebloatWireDoc? Debloat,
    [property: JsonPropertyName("packages")] PackagesWireDoc? Packages);

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
    [property: JsonPropertyName("removeProvisionedAppx")] string[]? RemoveProvisionedAppx,
    [property: JsonPropertyName("removeCapabilities")] string[]? RemoveCapabilities,
    [property: JsonPropertyName("disableOptionalFeatures")] string[]? DisableOptionalFeatures);

internal sealed record PackagesWireDoc(
    [property: JsonPropertyName("winget")] string[]? Winget,
    [property: JsonPropertyName("wingetNeedsReboot")] string[]? WingetNeedsReboot,
    [property: JsonPropertyName("scoop")] string[]? Scoop,
    [property: JsonPropertyName("scoopNeedsReboot")] string[]? ScoopNeedsReboot,
    [property: JsonPropertyName("wsl")] string[]? Wsl,
    [property: JsonPropertyName("wslNeedsReboot")] string[]? WslNeedsReboot);

[JsonSerializable(typeof(ProfileWireDoc))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class WizardProfileJsonContext : JsonSerializerContext;
