namespace WinMint.Wizard;

/// <summary>Unelevated reader for RunPlan <c>{work}/apply-status.txt</c> (Avalonia-free).</summary>
internal static class ApplyStatusReader
{
    public const string FileName = "apply-status.txt";

    public static string StatusPath(string workDirectory) =>
        Path.Combine(workDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), FileName);

    public static ApplyStatusSnapshot? TryRead(
        string statusFilePath,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(statusFilePath) || !File.Exists(statusFilePath))
        {
            return null;
        }

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            // ponytail: small status file; Share ReadWrite so elevated RunPlan can rewrite while we poll
            using FileStream stream = new(
                statusFilePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            using StreamReader reader = new(stream);
            string? stage = null;
            string? log = null;
            while (reader.ReadLine() is { } line)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (line.StartsWith("stage=", StringComparison.Ordinal))
                {
                    stage = line["stage=".Length..].Trim();
                }
                else if (line.StartsWith("log=", StringComparison.Ordinal))
                {
                    log = line["log=".Length..].Trim();
                }
            }

            if (stage is null)
            {
                return null;
            }

            return new ApplyStatusSnapshot(stage, string.IsNullOrWhiteSpace(log) ? null : log);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>
    /// Busy chrome label from a status snapshot.
    /// Null for missing/idle/<c>done</c> so the host keeps pre-Apply text or finalizes from Apply result.
    /// </summary>
    public static string? FormatBusyLabel(ApplyStatusSnapshot? snapshot)
    {
        if (snapshot is null || string.IsNullOrWhiteSpace(snapshot.Stage))
        {
            return null;
        }

        if (snapshot.Stage.Equals("idle", StringComparison.OrdinalIgnoreCase)
            || snapshot.Stage.Equals("done", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        string stage = snapshot.Stage;
        string prefix = stage.StartsWith("failed:", StringComparison.OrdinalIgnoreCase)
            ? "Failed"
            : "Building";
        string display = stage.StartsWith("failed:", StringComparison.OrdinalIgnoreCase)
            ? stage["failed:".Length..]
            : stage;

        if (!string.IsNullOrWhiteSpace(snapshot.LogPath))
        {
            return $"{prefix}: {display} — {snapshot.LogPath}";
        }

        return $"{prefix}: {display}";
    }
}

internal sealed record ApplyStatusSnapshot(string Stage, string? LogPath);
