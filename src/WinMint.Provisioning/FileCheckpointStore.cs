namespace WinMint.Provisioning;

/// <summary>
/// Heartbeat (+ optional checkpoint presence) under ProgramData.
/// Checkpoint write/clear for reboot resume is ticket 08.
/// </summary>
public sealed class FileCheckpointStore : ICheckpointStore
{
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
        // ponytail: existence of checkpoint.json = in-progress until ticket 08 writes a real schema.
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
        string? dir = Path.GetDirectoryName(_heartbeatPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        File.WriteAllText(_heartbeatPath, utcNow.ToString("o"));
    }
}
