using System.Diagnostics;

namespace WinMint.Orchestrator;

/// <summary>
/// UAC parent progress: stage changes + sparse still (log length growth) + one quiet warn.
/// Does not use apply-status <c>updated=</c> wall-clock age.
/// </summary>
public sealed class ApplyOperatorProgressTracker(
    TimeSpan? stillInterval = null,
    TimeSpan? quietAfter = null)
{
    private readonly TimeSpan _stillInterval = stillInterval ?? TimeSpan.FromSeconds(20);
    private readonly TimeSpan _quietAfter = quietAfter ?? TimeSpan.FromSeconds(60);
    private readonly Stopwatch _stillGate = new();
    private readonly Stopwatch _sinceGrowth = Stopwatch.StartNew();
    private string? _lastStage;
    private long _lastLogLength = -1;
    private bool _quietEmitted;

    public string? Consider(ApplyProgress? snapshot, long? logLength, bool cancelled)
    {
        if (cancelled)
        {
            return null;
        }

        if (snapshot is null || string.IsNullOrWhiteSpace(snapshot.Value.Stage))
        {
            return null;
        }

        string stage = snapshot.Value.Stage.Trim();
        bool idleOrDone = stage.Equals("idle", StringComparison.OrdinalIgnoreCase)
            || stage.Equals("done", StringComparison.OrdinalIgnoreCase);

        if (!string.Equals(stage, _lastStage, StringComparison.Ordinal))
        {
            _lastStage = stage;
            _lastLogLength = logLength ?? -1;
            _sinceGrowth.Restart();
            _quietEmitted = false;
            _stillGate.Reset();
            return idleOrDone ? null : FormatStageLine(stage, snapshot.Value.LogPath);
        }

        if (idleOrDone)
        {
            return null;
        }

        if (logLength is null)
        {
            return null;
        }

        long length = logLength.Value;
        if (_lastLogLength < 0)
        {
            _lastLogLength = length;
            return null;
        }

        if (length < _lastLogLength)
        {
            _lastLogLength = length;
            _sinceGrowth.Restart();
            _quietEmitted = false;
            return null;
        }

        if (length > _lastLogLength)
        {
            long delta = length - _lastLogLength;
            _lastLogLength = length;
            _sinceGrowth.Restart();
            _quietEmitted = false;
            if (!_stillGate.IsRunning || _stillGate.Elapsed >= _stillInterval)
            {
                _stillGate.Restart();
                string leaf = string.IsNullOrWhiteSpace(snapshot.Value.LogPath)
                    ? "log"
                    : Path.GetFileName(snapshot.Value.LogPath);
                return $"still {stage} ({leaf}, +{delta}B)";
            }

            return null;
        }

        if (!_quietEmitted && _sinceGrowth.Elapsed >= _quietAfter)
        {
            _quietEmitted = true;
            return $"quiet {stage} — no log growth";
        }

        return null;
    }

    public static long? TryGetLogLength(string? logPath)
    {
        if (string.IsNullOrWhiteSpace(logPath) || !File.Exists(logPath))
        {
            return null;
        }

        try
        {
            return new FileInfo(logPath).Length;
        }
        catch (IOException)
        {
            return null;
        }
    }

    private static string FormatStageLine(string stage, string? logPath)
    {
        if (string.IsNullOrWhiteSpace(logPath))
        {
            return stage;
        }

        return $"{stage} — {logPath}";
    }
}
