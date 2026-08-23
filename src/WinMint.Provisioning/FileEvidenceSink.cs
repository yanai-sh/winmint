using System.Text.Json;

namespace WinMint.Provisioning;

/// <summary>
/// Write-only evidence projection under %ProgramData%\WinMint\evidence\.
/// Session must never read these files to decide the next phase.
/// </summary>
public sealed class FileEvidenceSink(string directory) : IEvidenceSink
{
    public const string SchemaVersion = ProvisioningSession.EvidenceSchemaVersion;

    /// <summary>Sibling of the evidence folder: %ProgramData%\WinMint\smoke-run.id</summary>
    public const string SmokeRunIdFileName = "smoke-run.id";

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

        if (string.IsNullOrWhiteSpace(document.SmokeRunId))
        {
            string? stamped = TryReadSmokeRunId(_directory);
            if (!string.IsNullOrWhiteSpace(stamped))
            {
                document = document with { SmokeRunId = stamped };
            }
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

    /// <summary>Fail-open: missing/unreadable stamp is normal for Primary (no Smoke host).</summary>
    internal static string? TryReadSmokeRunId(string evidenceDirectory)
    {
        try
        {
            string? parent = Path.GetDirectoryName(Path.GetFullPath(evidenceDirectory));
            if (string.IsNullOrWhiteSpace(parent))
            {
                return null;
            }

            string path = Path.Combine(parent, SmokeRunIdFileName);
            if (!File.Exists(path))
            {
                return null;
            }

            string text = File.ReadAllText(path).Trim();
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch
        {
            return null;
        }
    }
}
