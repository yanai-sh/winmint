using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Provisioning;

/// <summary>
/// Heartbeat + checkpoint under ProgramData (`winmint.provisioning.checkpoint/v1`).
/// </summary>
public sealed class FileCheckpointStore : ICheckpointStore
{
    public const string CheckpointSchemaVersion = "winmint.provisioning.checkpoint/v1";

    private readonly string _checkpointPath;
    private readonly string _heartbeatPath;

    public FileCheckpointStore(string programDataRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(programDataRoot);
        _checkpointPath = Path.Combine(programDataRoot, "checkpoint.json");
        _heartbeatPath = Path.Combine(programDataRoot, "heartbeat");
    }

    public TenureState ReadTenure()
    {
        bool inProgress = File.Exists(_checkpointPath);
        DateTimeOffset? heartbeat = null;
        if (File.Exists(_heartbeatPath))
        {
            string text = File.ReadAllText(_heartbeatPath).Trim();
            if (DateTimeOffset.TryParse(
                    text,
                    null,
                    System.Globalization.DateTimeStyles.RoundtripKind,
                    out DateTimeOffset parsed))
            {
                heartbeat = parsed;
            }
        }

        return new TenureState(inProgress, heartbeat);
    }

    public void WriteHeartbeat(DateTimeOffset utcNow)
    {
        EnsureDir(_heartbeatPath);
        File.WriteAllText(_heartbeatPath, utcNow.ToString("o"));
    }

    public void WriteCheckpoint(CheckpointState state)
    {
        EnsureDir(_checkpointPath);
        CheckpointFile file = new(CheckpointSchemaVersion, state.Phase);
        string json = JsonSerializer.Serialize(file, CheckpointJsonContext.Default.CheckpointFile);
        File.WriteAllText(_checkpointPath, json);
    }

    public CheckpointState? TryReadCheckpoint()
    {
        if (!File.Exists(_checkpointPath))
        {
            return null;
        }

        try
        {
            byte[] bytes = File.ReadAllBytes(_checkpointPath);
            CheckpointFile? file = JsonSerializer.Deserialize(bytes, CheckpointJsonContext.Default.CheckpointFile);
            if (file is null
                || !string.Equals(file.SchemaVersion, CheckpointSchemaVersion, StringComparison.Ordinal)
                || string.IsNullOrWhiteSpace(file.Phase))
            {
                return null;
            }

            return new CheckpointState(file.Phase);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public void ClearCheckpoint()
    {
        if (File.Exists(_checkpointPath))
        {
            File.Delete(_checkpointPath);
        }
    }

    private static void EnsureDir(string path)
    {
        string? dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }
    }
}

internal sealed record CheckpointFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("phase")] string Phase);

[JsonSerializable(typeof(CheckpointFile))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class CheckpointJsonContext : JsonSerializerContext;
