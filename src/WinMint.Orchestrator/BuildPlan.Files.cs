using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class BuildPlan
{
    /// <summary>Cli plan file shape for <c>manifest.json</c> (includes RequiresNetwork — #90 honesty).</summary>
    public static string SerializeManifestFile(BuildManifest manifest) =>
        JsonSerializer.Serialize(
            new ManifestFile(manifest.ImageQuality.ToString(), manifest.RequiresNetwork),
            PlanFileJsonContext.Default.ManifestFile);

    /// <summary>Write guest <c>jobs.json</c> — the file BundleLoader reads back in the guest.</summary>
    public static string SerializeJobsFile(JobsArtifact jobs) =>
        JsonSerializer.Serialize(
            new JobsFile(jobs.SchemaVersion, [.. jobs.Jobs.Select(static j => j.ToWire())]),
            PlanFileJsonContext.Default.JobsFile);

    public static string SerializeStagesFile(ServicingStageList stages) =>
        JsonSerializer.Serialize(
            new StagesFile(
                StagesSchemaVersion,
                stages.Stages.Select(static s => new StageFile(
                    s.Opcode.ToString(),
                    s.Parameters.ToDictionary(static kv => kv.Key, static kv => kv.Value, StringComparer.Ordinal)))
                    .ToArray()),
            PlanFileJsonContext.Default.StagesFile);
}

internal sealed record ManifestFile(
    [property: JsonPropertyName("imageQuality")] string ImageQuality,
    [property: JsonPropertyName("requiresNetwork")] bool RequiresNetwork);

internal sealed record StagesFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("stages")] IReadOnlyList<StageFile> Stages);

internal sealed record StageFile(
    [property: JsonPropertyName("opcode")] string Opcode,
    [property: JsonPropertyName("parameters")] Dictionary<string, string> Parameters);

[JsonSerializable(typeof(ManifestFile))]
[JsonSerializable(typeof(JobsFile))]
[JsonSerializable(typeof(StagesFile))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PlanFileJsonContext : JsonSerializerContext;
