using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Contracts;

/// <summary>
/// Guest <c>jobs.json</c> interchange (BuildPlan write / BundleLoader read) and the job shape both
/// sides plan and execute. One schema constant, one wire record, one domain record — a new job field
/// is one edit here plus the two mappers that cross this seam.
/// </summary>
public static class JobsWire
{
    public const string SchemaVersion = "winmint.jobs/v1";

    public static string Write(IReadOnlyList<ProvisionJob> jobs)
    {
        ArgumentNullException.ThrowIfNull(jobs);
        return JsonSerializer.Serialize(
            new JobsFile(SchemaVersion, [.. jobs.Select(static job => job.ToWire())]),
            JobsWireJsonContext.Default.JobsFile);
    }

    public static bool TryParse(
        ReadOnlySpan<byte> utf8,
        [NotNullWhen(true)] out JobsFile? file,
        out JobsWireError error)
    {
        try
        {
            file = JsonSerializer.Deserialize(utf8, JobsWireJsonContext.Default.JobsFile);
        }
        catch (JsonException ex)
        {
            file = null;
            error = new JobsWireError("jobs.parse", $"Failed to parse jobs: {ex.Message}");
            return false;
        }

        if (file is null)
        {
            error = new JobsWireError("jobs.parse", "Failed to parse jobs.");
            return false;
        }

        if (!string.Equals(file.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            error = new JobsWireError(
                "jobs.schema",
                $"Unsupported jobs schema '{file.SchemaVersion}' (need {SchemaVersion}).");
            return false;
        }

        error = default;
        return true;
    }
}

public readonly record struct JobsWireError(string Code, string Message);

public sealed record JobsFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("jobs")] JobFile[]? Jobs);

/// <summary>
/// Wire shape: <c>kind</c> and <c>wslInstallKind</c> are wire strings, and absent means default —
/// the writer elides nulls, so the reader must treat every optional member as optional.
/// </summary>
public sealed record JobFile(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("needsReboot")] bool NeedsReboot = false,
    [property: JsonPropertyName("packageId")] string? PackageId = null,
    [property: JsonPropertyName("wingetArchitecture")] string? WingetArchitecture = null,
    [property: JsonPropertyName("wslInstallKind")] string? WslInstallKind = null,
    [property: JsonPropertyName("wslFromFileRepo")] string? WslFromFileRepo = null,
    [property: JsonPropertyName("wslFromFileAssetNames")] string[]? WslFromFileAssetNames = null,
    [property: JsonPropertyName("auditStrict")] bool? AuditStrict = null,
    [property: JsonPropertyName("scoopBuckets")] string[]? ScoopBuckets = null,
    [property: JsonPropertyName("dohPrimary")] string? DohPrimary = null,
    [property: JsonPropertyName("dohSecondary")] string? DohSecondary = null,
    [property: JsonPropertyName("dohTemplate")] string? DohTemplate = null);

/// <summary>Planned job with a closed <see cref="ProvisionJobKind"/>; what BuildPlan emits and JobRunner executes.</summary>
public sealed record ProvisionJob(
    string Id,
    ProvisionJobKind Kind,
    bool NeedsReboot = false,
    string? PackageId = null,
    string? WingetArchitecture = null,
    WslInstallKind? WslInstallKind = null,
    string? WslFromFileRepo = null,
    IReadOnlyList<string>? WslFromFileAssetNames = null,
    bool AuditStrict = false,
    IReadOnlyList<string>? ScoopBuckets = null,
    string? DohPrimary = null,
    string? DohSecondary = null,
    string? DohTemplate = null)
{
    /// <summary>Project to the wire shape, eliding what the reader defaults anyway.</summary>
    public JobFile ToWire() =>
        new(
            Id,
            Kind.ToWire(),
            NeedsReboot,
            PackageId,
            WingetArchitecture,
            WslInstallKind?.ToWire(),
            WslFromFileRepo,
            WslFromFileAssetNames is { Count: > 0 } ? [.. WslFromFileAssetNames] : null,
            AuditStrict ? true : null,
            ScoopBuckets is { Count: > 0 } ? [.. ScoopBuckets] : null,
            DohPrimary,
            DohSecondary,
            DohTemplate);
}

[JsonSerializable(typeof(JobsFile))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class JobsWireJsonContext : JsonSerializerContext;
