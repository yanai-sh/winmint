namespace WinMint.Provisioning;

/// <summary>Heartbeat + checkpoint under ProgramData (plain phase string, same shape as heartbeat).</summary>
public sealed class FileCheckpointStore : ICheckpointStore
{
    private readonly string _checkpointPath;
    private readonly string _heartbeatPath;
    private readonly string _tenurePhasePath;

    public FileCheckpointStore(string programDataRoot)
    {
        string root = RequireRoot(programDataRoot);
        _checkpointPath = Path.Combine(root, "checkpoint.json");
        _heartbeatPath = Path.Combine(root, "heartbeat");
        _tenurePhasePath = Path.Combine(root, "tenure-phase");
    }

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

    public void WriteTenurePhase(string code)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(code);
        try
        {
            EnsureDir(_tenurePhasePath);
            File.WriteAllText(_tenurePhasePath, code);
        }
        catch
        {
            // ponytail: breadcrumb only — mid-settle death diagnosis; never fail tenure
        }
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
