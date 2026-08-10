using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

public readonly record struct BundleLoadError(string Code, string Message);

/// <summary>Load outcome for guest bundle + jobs.json (Provisioning-local; no Orchestrator ref).</summary>
public readonly struct BundleLoadResult
{
    private readonly ProvisioningBundle? _bundle;
    private readonly BundleLoadError _error;

    private BundleLoadResult(bool isOk, ProvisioningBundle? bundle, BundleLoadError error)
    {
        IsOk = isOk;
        _bundle = bundle;
        _error = error;
    }

    public bool IsOk { get; }

    public ProvisioningBundle Value => IsOk
        ? _bundle!
        : throw new InvalidOperationException("Bundle load failed.");

    public BundleLoadError Error => !IsOk
        ? _error
        : throw new InvalidOperationException("Bundle load succeeded.");

    public static BundleLoadResult Ok(ProvisioningBundle bundle) => new(true, bundle, default);

    public static BundleLoadResult Fail(BundleLoadError error) => new(false, null, error);
}

public static class BundleLoader
{
    public const string SchemaVersion = "winmint.provisioning.bundle/v1";
    public const string JobsSchemaVersion = "winmint.jobs/v1";
    public const string DefaultGuestBundlePath = @"C:\Windows\WinMint\bundle.json";
    public const string DefaultGuestWingetImportPath = @"C:\Windows\WinMint\winget-import.json";

    public static BundleLoadResult LoadFromFile(string path)
    {
        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.read", $"Failed to read bundle: {path}: {ex.Message}"));
        }

        BundleFile? dto;
        try
        {
            dto = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.BundleFile);
        }
        catch (JsonException ex)
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.parse", $"Failed to parse bundle: {path}: {ex.Message}"));
        }

        if (dto is null)
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.parse", $"Failed to parse bundle: {path}"));
        }

        if (!string.Equals(dto.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            return BundleLoadResult.Fail(
                new BundleLoadError(
                    "bundle.schema",
                    $"Unsupported bundle schema '{dto.SchemaVersion}' (need {SchemaVersion})."));
        }

        if (string.IsNullOrWhiteSpace(dto.SupervisorPath))
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.required", "bundle.supervisorPath is required."));
        }

        if (string.IsNullOrWhiteSpace(dto.Username))
        {
            return BundleLoadResult.Fail(
                new BundleLoadError("bundle.required", "bundle.username is required."));
        }

        string? dir = Path.GetDirectoryName(path);
        string jobsPath = dir is null ? "jobs.json" : Path.Combine(dir, "jobs.json");
        if (!TryLoadJobs(jobsPath, out IReadOnlyList<ProvisionJob> jobs, out BundleLoadError jobsError))
        {
            return BundleLoadResult.Fail(jobsError);
        }

        return BundleLoadResult.Ok(
            new ProvisioningBundle(
                Account: new AccountStamp(dto.Username, dto.Password ?? ""),
                Dma: new DmaSettleTarget(
                    dto.DmaEnabled,
                    dto.Settle?.Locale,
                    dto.Settle?.GeoId,
                    dto.Settle?.TimeZoneId,
                    dto.Settle?.LocationServicesEnabled),
                Jobs: jobs,
                Policy: SessionPolicy.SmokeDefaults,
                SupervisorShellPath: dto.SupervisorPath,
                RemoveProvisionedAppx: dto.RemoveProvisionedAppx ?? [],
                RequiresNetwork: dto.RequiresNetwork,
                PackageStrict: dto.PackageStrict));
    }

    private static bool TryLoadJobs(
        string jobsPath,
        out IReadOnlyList<ProvisionJob> jobs,
        out BundleLoadError error)
    {
        jobs = [];
        error = default;

        if (!File.Exists(jobsPath))
        {
            error = new BundleLoadError("jobs.missing", $"jobs.json required beside bundle (missing: {jobsPath}).");
            return false;
        }

        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(jobsPath);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            error = new BundleLoadError("jobs.read", $"Failed to read jobs: {jobsPath}: {ex.Message}");
            return false;
        }

        JobsFile? jobsFile;
        try
        {
            jobsFile = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.JobsFile);
        }
        catch (JsonException ex)
        {
            error = new BundleLoadError("jobs.parse", $"Failed to parse jobs: {jobsPath}: {ex.Message}");
            return false;
        }

        if (jobsFile is null)
        {
            error = new BundleLoadError("jobs.parse", $"Failed to parse jobs: {jobsPath}");
            return false;
        }

        if (!string.Equals(jobsFile.SchemaVersion, JobsSchemaVersion, StringComparison.Ordinal))
        {
            error = new BundleLoadError(
                "jobs.schema",
                $"Unsupported jobs schema '{jobsFile.SchemaVersion}' (need {JobsSchemaVersion}).");
            return false;
        }

        List<ProvisionJob> list = [];
        foreach (JobFile j in jobsFile.Jobs ?? [])
        {
            if (!ProvisionJobKindWire.TryParse(j.Kind, out ProvisionJobKind kind))
            {
                error = new BundleLoadError(
                    "jobs.kind.unknown",
                    $"Unsupported job kind '{j.Kind}' for id '{j.Id}'.");
                return false;
            }

            list.Add(
                new ProvisionJob(
                    j.Id,
                    kind,
                    j.NeedsReboot,
                    j.PackageId,
                    j.WingetArchitecture,
                    j.WslInstallKind,
                    j.WslFromFileRepo,
                    j.WslFromFileAssetNames,
                    j.AuditStrict,
                    j.ScoopBuckets,
                    j.DohPrimary,
                    j.DohSecondary,
                    j.DohTemplate));
        }

        jobs = list;
        return true;
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
    [property: JsonPropertyName("scoopBuckets")] string[]? ScoopBuckets = null,
    [property: JsonPropertyName("dohPrimary")] string? DohPrimary = null,
    [property: JsonPropertyName("dohSecondary")] string? DohSecondary = null,
    [property: JsonPropertyName("dohTemplate")] string? DohTemplate = null);

[JsonSerializable(typeof(BundleFile))]
[JsonSerializable(typeof(JobsFile))]
[JsonSerializable(typeof(ProvisioningEvidenceDocument))]
[JsonSerializable(typeof(PackagesEvidenceDocument))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ProvisioningJsonContext : JsonSerializerContext;
