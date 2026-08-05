using System.Text.Json;

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
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(
            document,
            ProvisioningJsonContext.Default.ProvisioningEvidenceDocument);
        File.WriteAllBytes(path, bytes);
        return new EvidenceSnapshot(SchemaVersion, path);
    }
}
