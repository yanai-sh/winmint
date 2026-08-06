using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

public static class BundleLoader
{
    public const string SchemaVersion = "winmint.provisioning.bundle/v1";
    public const string JobsSchemaVersion = "winmint.jobs/v1";
    public const string DefaultGuestBundlePath = @"C:\Windows\WinMint\bundle.json";
    public const string DefaultGuestWingetImportPath = @"C:\Windows\WinMint\winget-import.json";

    public static ProvisioningBundle LoadFromFile(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        BundleFile? dto = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.BundleFile);
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

        string? dir = Path.GetDirectoryName(path);
        string jobsPath = dir is null ? "jobs.json" : Path.Combine(dir, "jobs.json");
        IReadOnlyList<ProvisionJob> jobs = LoadJobs(jobsPath);

        return new ProvisioningBundle(
            Account: new AccountStamp(dto.Username, dto.Password ?? ""),
            Dma: new DmaSettleTarget(
                dto.DmaEnabled,
                dto.Settle?.Locale,
                dto.Settle?.GeoId,
                dto.Settle?.TimeZoneId,
                dto.Settle?.LocationServicesEnabled),
            Jobs: jobs,
            Policy: SessionPolicy.SmokeDefaults,
            Supervisor: new SupervisorIdentity(dto.SupervisorPath),
            RemoveProvisionedAppx: dto.RemoveProvisionedAppx ?? [],
            RequiresNetwork: dto.RequiresNetwork,
            PackageStrict: dto.PackageStrict);
    }

    private static ProvisionJob[] LoadJobs(string jobsPath)
    {
        if (!File.Exists(jobsPath))
        {
            throw new InvalidOperationException($"jobs.json required beside bundle (missing: {jobsPath}).");
        }

        byte[] bytes = File.ReadAllBytes(jobsPath);
        JobsFile? jobsFile = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.JobsFile);
        if (jobsFile is null)
        {
            throw new InvalidOperationException($"Failed to parse jobs: {jobsPath}");
        }

        if (!string.Equals(jobsFile.SchemaVersion, JobsSchemaVersion, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Unsupported jobs schema '{jobsFile.SchemaVersion}' (need {JobsSchemaVersion}).");
        }

        return (jobsFile.Jobs ?? [])
            .Select(j => new ProvisionJob(
                j.Id,
                j.Kind,
                j.NeedsReboot,
                j.PackageId,
                j.WingetArchitecture,
                j.WslInstallKind,
                j.WslFromFileRepo,
                j.WslFromFileAssetNames,
                j.AuditStrict,
                j.ScoopBuckets))
            .ToArray();
    }
}

internal sealed record BundleFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("supervisorPath")] string SupervisorPath,
    [property: JsonPropertyName("username")] string Username,
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("dmaEnabled")] bool DmaEnabled,
    [property: JsonPropertyName("settle")] SettleFile? Settle,
    [property: JsonPropertyName("removeProvisionedAppx")] string[]? RemoveProvisionedAppx,
    [property: JsonPropertyName("requiresNetwork")] bool RequiresNetwork = false,
    [property: JsonPropertyName("packageStrict")] bool PackageStrict = false);

internal sealed record SettleFile(
    [property: JsonPropertyName("locale")] string Locale,
    [property: JsonPropertyName("geoId")] int GeoId,
    [property: JsonPropertyName("timeZoneId")] string TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool LocationServicesEnabled);

internal sealed record JobsFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("jobs")] JobFile[]? Jobs);

internal sealed record JobFile(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("needsReboot")] bool NeedsReboot = false,
    [property: JsonPropertyName("packageId")] string? PackageId = null,
    [property: JsonPropertyName("wingetArchitecture")] string? WingetArchitecture = null,
    [property: JsonPropertyName("wslInstallKind")] string? WslInstallKind = null,
    [property: JsonPropertyName("wslFromFileRepo")] string? WslFromFileRepo = null,
    [property: JsonPropertyName("wslFromFileAssetNames")] string[]? WslFromFileAssetNames = null,
    [property: JsonPropertyName("auditStrict")] bool AuditStrict = false,
    [property: JsonPropertyName("scoopBuckets")] string[]? ScoopBuckets = null);

[JsonSerializable(typeof(BundleFile))]
[JsonSerializable(typeof(JobsFile))]
[JsonSerializable(typeof(ProvisioningEvidenceDocument))]
[JsonSerializable(typeof(PackagesEvidenceDocument))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ProvisioningJsonContext : JsonSerializerContext;
