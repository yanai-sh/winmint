using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class BuildPlan
{
    /// <summary>Cli plan-dump shape for <c>manifest.json</c> (includes RequiresNetwork — #90 honesty).</summary>
    public static string SerializeManifestDump(BuildManifest manifest) =>
        JsonSerializer.Serialize(
            new ManifestDump(manifest.ImageQuality.ToString(), manifest.RequiresNetwork),
            PlanDumpJsonContext.Default.ManifestDump);

    public static string SerializeJobsDump(JobsArtifact jobs) =>
        JsonSerializer.Serialize(
            new JobsDump(
                jobs.SchemaVersion,
                jobs.Jobs.Select(static j => new JobDump(
                    j.Id,
                    j.Kind.ToWire(),
                    j.NeedsReboot,
                    j.PackageId,
                    j.WingetArchitecture,
                    j.WslInstallKind?.ToWire(),
                    j.WslFromFileRepo,
                    j.WslFromFileAssetNames is { Count: > 0 } ? j.WslFromFileAssetNames : null,
                    j.AuditStrict ? true : null,
                    j.ScoopBuckets is { Count: > 0 } ? j.ScoopBuckets : null,
                    j.DohPrimary,
                    j.DohSecondary,
                    j.DohTemplate)).ToArray()),
            PlanDumpJsonContext.Default.JobsDump);

    public static string SerializeStagesDump(ServicingStageList stages) =>
        JsonSerializer.Serialize(
            new StagesDump(
                StagesSchemaVersion,
                stages.Stages.Select(static s => new StageDump(
                    s.Opcode.ToString(),
                    s.Parameters.ToDictionary(static kv => kv.Key, static kv => kv.Value, StringComparer.Ordinal)))
                    .ToArray()),
            PlanDumpJsonContext.Default.StagesDump);
}

internal sealed record ManifestDump(
    [property: JsonPropertyName("imageQuality")] string ImageQuality,
    [property: JsonPropertyName("requiresNetwork")] bool RequiresNetwork);

internal sealed record JobsDump(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("jobs")] IReadOnlyList<JobDump> Jobs);

internal sealed record JobDump(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("needsReboot")] bool NeedsReboot,
    [property: JsonPropertyName("packageId")] string? PackageId = null,
    [property: JsonPropertyName("wingetArchitecture")] string? WingetArchitecture = null,
    [property: JsonPropertyName("wslInstallKind")] string? WslInstallKind = null,
    [property: JsonPropertyName("wslFromFileRepo")] string? WslFromFileRepo = null,
    [property: JsonPropertyName("wslFromFileAssetNames")] IReadOnlyList<string>? WslFromFileAssetNames = null,
    [property: JsonPropertyName("auditStrict")] bool? AuditStrict = null,
    [property: JsonPropertyName("scoopBuckets")] IReadOnlyList<string>? ScoopBuckets = null,
    [property: JsonPropertyName("dohPrimary")] string? DohPrimary = null,
    [property: JsonPropertyName("dohSecondary")] string? DohSecondary = null,
    [property: JsonPropertyName("dohTemplate")] string? DohTemplate = null);

internal sealed record StagesDump(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("stages")] IReadOnlyList<StageDump> Stages);

internal sealed record StageDump(
    [property: JsonPropertyName("opcode")] string Opcode,
    [property: JsonPropertyName("parameters")] Dictionary<string, string> Parameters);

[JsonSerializable(typeof(ManifestDump))]
[JsonSerializable(typeof(JobsDump))]
[JsonSerializable(typeof(StagesDump))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PlanDumpJsonContext : JsonSerializerContext;
