using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

/// <summary>
/// Write-only evidence projection under %ProgramData%\WinMint\evidence\.
/// Session must never read these files to decide the next phase.
/// </summary>
public sealed class FileEvidenceSink : IEvidenceSink
{
    public const string SchemaVersion = ProvisioningSession.EvidenceSchemaVersion;

    private readonly string _directory;

    public FileEvidenceSink(string directory)
    {
        _directory = directory;
    }

    public EvidenceSnapshot Write(ProvisioningEvidenceDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);
        if (!string.Equals(document.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Evidence schema '{document.SchemaVersion}' must be '{SchemaVersion}'.");
        }

        Directory.CreateDirectory(_directory);
        string path = Path.Combine(_directory, $"evidence-{DateTimeOffset.UtcNow:yyyyMMddHHmmssfff}.json");
        EvidenceDto dto = new(
            document.SchemaVersion,
            document.Outcome,
            document.StatusCode,
            document.StatusMessage,
            document.Phases.ToArray());
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(dto, ProvisioningJsonContext.Default.EvidenceDto);
        File.WriteAllBytes(path, bytes);
        return new EvidenceSnapshot(SchemaVersion, path);
    }
}

internal sealed record EvidenceDto(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("outcome")] string Outcome,
    [property: JsonPropertyName("statusCode")] string StatusCode,
    [property: JsonPropertyName("statusMessage")] string StatusMessage,
    [property: JsonPropertyName("phases")] string[] Phases);
