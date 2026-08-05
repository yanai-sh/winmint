namespace WinMint.Provisioning;

/// <summary>Heartbeat + checkpoint under ProgramData (plain phase string, same shape as heartbeat).</summary>
public sealed class FileCheckpointStore(string programDataRoot) : ICheckpointStore
{
    private readonly string _checkpointPath = Path.Combine(RequireRoot(programDataRoot), "checkpoint.json");
    private readonly string _heartbeatPath = Path.Combine(RequireRoot(programDataRoot), "heartbeat");

    private static string RequireRoot(string programDataRoot)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(programDataRoot);
        return programDataRoot;
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
        File.WriteAllText(_checkpointPath, state.Phase);
    }

    public CheckpointState? TryReadCheckpoint()
    {
        if (!File.Exists(_checkpointPath))
        {
            return null;
        }

        string phase = File.ReadAllText(_checkpointPath).Trim();
        return string.IsNullOrWhiteSpace(phase) ? null : new CheckpointState(phase);
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
