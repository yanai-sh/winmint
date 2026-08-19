using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

public static partial class BuildPlan
{
    /// <summary>Cli plan file shape for <c>manifest.json</c> (includes RequiresNetwork — #90 honesty).</summary>
    public static string SerializeManifestFile(BuildManifest manifest) =>
        JsonSerializer.Serialize(
            new ManifestFile(manifest.ImageQuality.ToString(), manifest.RequiresNetwork),
            PlanFileJsonContext.Default.ManifestFile);

    public static string SerializePlanStagesFile(
        IReadOnlyList<ServicingOpcode> stages,
        DriverInject? drivers = null,
        ImageQualityLane lane = ImageQualityLane.Test)
    {
        ExportLane export = ExportLane.For(lane);
        Dictionary<string, string> empty = [];
        return JsonSerializer.Serialize(
            new StagesFile(
                PlanStagesSchemaVersion,
                [.. stages.Select(opcode => new StageFile(
                    opcode.ToString(),
                    opcode switch
                    {
                        ServicingOpcode.InjectDrivers when drivers is not null => new Dictionary<string, string>(StringComparer.Ordinal)
                        {
                            [StageParams.DeviceId] = drivers.DeviceId,
                            [StageParams.DetailsUrl] = drivers.DetailsUrl,
                            [StageParams.ExpectedFileNameRegex] = drivers.ExpectedFileNameRegex,
                        },
                        ServicingOpcode.ExportWim => new Dictionary<string, string>(StringComparer.Ordinal)
                        {
                            [StageParams.Lane] = export.Name,
                            [StageParams.Compression] = export.Compression,
                            [StageParams.Cleanup] = export.Cleanup,
                        },
                        _ => empty,
                    }))]),
            PlanFileJsonContext.Default.StagesFile);
    }
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
[JsonSerializable(typeof(StagesFile))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PlanFileJsonContext : JsonSerializerContext;
