using System.Text.Json;

namespace WinMint.Provisioning;

/// <summary>
/// Write-only evidence projection under %ProgramData%\WinMint\evidence\.
/// Session must never read these files to decide the next phase.
/// </summary>
public sealed class FileEvidenceSink(string directory) : IEvidenceSink
{
    public const string SchemaVersion = ProvisioningSession.EvidenceSchemaVersion;

    private readonly string _directory = RequireDir(directory);

    private static string RequireDir(string directory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        return directory;
    }

    public EvidenceSnapshot Write(ProvisioningEvidenceFile document)
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
            ProvisioningJsonContext.Default.ProvisioningEvidenceFile);
        File.WriteAllBytes(path, bytes);
        return new EvidenceSnapshot(SchemaVersion, path);
    }

    public EvidenceSnapshot Write(PackagesEvidenceFile document)
    {
        ArgumentNullException.ThrowIfNull(document);
        if (!string.Equals(
                document.SchemaVersion,
                ProvisioningSession.PackagesEvidenceSchemaVersion,
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Package evidence schema '{document.SchemaVersion}' must be '{ProvisioningSession.PackagesEvidenceSchemaVersion}'.");
        }

        Directory.CreateDirectory(_directory);
        string path = Path.Combine(_directory, "packages.evidence.json");
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(
            document,
            ProvisioningJsonContext.Default.PackagesEvidenceFile);
        File.WriteAllBytes(path, bytes);
        return new EvidenceSnapshot(document.SchemaVersion, path);
    }
}
