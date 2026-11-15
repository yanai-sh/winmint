using System.Globalization;

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
            string first = File.ReadAllText(_heartbeatPath)
                .Replace("\r\n", "\n", StringComparison.Ordinal)
                .Split('\n', 2)[0]
                .Trim();
            if (DateTimeOffset.TryParse(
                    first,
                    CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.RoundtripKind,
                    out DateTimeOffset parsed))
            {
                heartbeat = parsed;
            }
        }

        (long? bootId, string? phase, int? resumeCount) = ReadBootStamp();
        return new TenureState(inProgress, heartbeat, bootId, phase, resumeCount);
    }

    public void WriteHeartbeat(DateTimeOffset utcNow, long? bootId, string? phase, int? resumeCount)
    {
        EnsureDir(_heartbeatPath);
        string utc = utcNow.ToString("o", CultureInfo.InvariantCulture);
        string body = bootId is long boot && resumeCount is int count
            ? string.Join(
                '\n',
                utc,
                boot.ToString(CultureInfo.InvariantCulture),
                (phase ?? "").Replace("\r", "", StringComparison.Ordinal).Replace("\n", "", StringComparison.Ordinal),
                count.ToString(CultureInfo.InvariantCulture))
            : utc;
        File.WriteAllText(_heartbeatPath, body);
    }

    private (long? BootId, string? Phase, int? ResumeCount) ReadBootStamp()
    {
        if (!File.Exists(_heartbeatPath))
        {
            return (null, null, null);
        }

        string[] lines = File.ReadAllText(_heartbeatPath)
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Split('\n');
        if (lines.Length > 0 && lines[^1].Length == 0)
        {
            lines = lines[..^1];
        }

        if (lines.Length < 4
            || !long.TryParse(lines[1].Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out long bootId)
            || !int.TryParse(lines[3].Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int resumeCount))
        {
            return (null, null, null);
        }

        return (bootId, lines[2], resumeCount);
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
