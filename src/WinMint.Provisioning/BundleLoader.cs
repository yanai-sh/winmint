using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

public static class BundleLoader
{
    public const string SchemaVersion = "winmint.provisioning.bundle/v1";
    public const string DefaultGuestBundlePath = @"C:\Windows\WinMint\bundle.json";

    public static ProvisioningBundle LoadFromFile(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        BundleDto? dto = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.BundleDto);
        if (dto is null)
        {
            throw new InvalidOperationException($"Failed to parse bundle: {path}");
        }

        if (!string.Equals(dto.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Unsupported bundle schema '{dto.SchemaVersion}' (need {SchemaVersion}).");
        }

        if (string.IsNullOrWhiteSpace(dto.SupervisorPath))
        {
            throw new InvalidOperationException("bundle.supervisorPath is required.");
        }

        if (string.IsNullOrWhiteSpace(dto.Username))
        {
            throw new InvalidOperationException("bundle.username is required.");
        }

        return new ProvisioningBundle(
            Account: new AccountStamp(dto.Username, dto.Password ?? ""),
            Dma: new DmaSettleTarget(
                dto.DmaEnabled,
                dto.Settle?.Locale,
                dto.Settle?.GeoId,
                dto.Settle?.TimeZoneId,
                dto.Settle?.LocationServicesEnabled),
            Jobs: (dto.JobIds ?? []).Select(id => new ProvisionJob(id, "stub")).ToArray(),
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(dto.SupervisorPath));
    }
}

internal sealed record BundleDto(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("supervisorPath")] string SupervisorPath,
    [property: JsonPropertyName("username")] string Username,
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("dmaEnabled")] bool DmaEnabled,
    [property: JsonPropertyName("settle")] SettleDto? Settle,
    [property: JsonPropertyName("jobIds")] string[]? JobIds);

internal sealed record SettleDto(
    [property: JsonPropertyName("locale")] string Locale,
    [property: JsonPropertyName("geoId")] int GeoId,
    [property: JsonPropertyName("timeZoneId")] string TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool LocationServicesEnabled);

[JsonSerializable(typeof(BundleDto))]
[JsonSerializable(typeof(EvidenceDto))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ProvisioningJsonContext : JsonSerializerContext;
