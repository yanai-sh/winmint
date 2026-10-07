using System.Text.Json;
using System.Text.RegularExpressions;

using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

internal readonly record struct ApplyBuildPresentation(
    string StageLine,
    string AliveLine,
    string StatusTail,
    double? ProgressPercent,
    bool IsProgressIndeterminate,
    string? StepCue,
    string? FailureDetail,
    string? TranscriptHint)
{
    public override string ToString() =>
        string.IsNullOrEmpty(StatusTail)
            ? StageLine
            : StageLine + Environment.NewLine + StatusTail;
}

internal static partial class ApplyBuildPresentationFormat
{
    private static readonly Regex QualityHashPercent = QualityHashPercentRegex();
    private static readonly Regex ApplyStepIndex = ApplyStepIndexRegex();
    private static readonly Regex AliveHeartbeatMatch = AliveHeartbeatRegex();

    private static readonly JsonSerializerOptions FailureJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    internal static bool IsTrailHeartbeatLine(string line) =>
        !string.IsNullOrWhiteSpace(line) && TrailHeartbeat().IsMatch(line);

    internal static bool IsDismProgressBarLine(string line) =>
        !string.IsNullOrWhiteSpace(line) && DismProgressBar().IsMatch(line);

    internal static bool ShouldShowInStatusTail(string line) =>
        !string.IsNullOrWhiteSpace(line)
        && !IsTrailHeartbeatLine(line)
        && !IsDismProgressBarLine(line);

    internal static ApplyBuildPresentation? FromApplyProgress(
        ApplyProgress? snapshot,
        Func<string, IReadOnlyList<string>>? readLogTail = null,
        int tailLines = 20,
        string? workDirectory = null)
    {
        if (snapshot is null || string.IsNullOrWhiteSpace(snapshot.Value.Stage))
        {
            return null;
        }

        string stage = snapshot.Value.Stage;
        if (stage.Equals("idle", StringComparison.OrdinalIgnoreCase)
            || stage.Equals("done", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        bool failed = stage.StartsWith("failed:", StringComparison.OrdinalIgnoreCase);
        string display = failed ? stage["failed:".Length..] : stage;
        string stageLine = failed ? $"Failed: {display}" : $"Building: {display}";

        IReadOnlyList<string> rawLines = [];
        if (!string.IsNullOrWhiteSpace(snapshot.Value.LogPath))
        {
            try
            {
                Func<string, IReadOnlyList<string>> reader = readLogTail ?? ReadSharedLogLines;
                rawLines = reader(snapshot.Value.LogPath);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        double? progressPercent = TryParseLatestQualityHashPercent(rawLines);
        string? stepCue = TryParseLatestApplyStepCue(rawLines);
        string aliveLine = FormatAliveLine(rawLines);
        IEnumerable<string> filtered = rawLines.Where(ShouldShowInStatusTail);
        string statusTail = string.Join(
            Environment.NewLine,
            filtered.TakeLast(Math.Max(0, tailLines)));

        string? failureDetail = null;
        string? transcriptHint = null;
        if (!string.IsNullOrWhiteSpace(workDirectory))
        {
            if (failed)
            {
                failureDetail = TryReadFailureMessage(workDirectory);
            }

            string transcriptPath = Path.Combine(workDirectory, "dism-transcript.log");
            if (File.Exists(transcriptPath))
            {
                transcriptHint = $"DISM transcript: {transcriptPath}";
            }
        }

        bool indeterminate = progressPercent is null;
        return new ApplyBuildPresentation(
            stageLine,
            aliveLine,
            statusTail,
            progressPercent,
            indeterminate,
            stepCue,
            failureDetail,
            transcriptHint);
    }

    internal static string FormatAliveLine(IEnumerable<string> lines)
    {
        foreach (string line in lines.Reverse())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            Match match = AliveHeartbeatMatch.Match(line);
            if (!match.Success)
            {
                continue;
            }

            if (!int.TryParse(match.Groups[2].Value, out int seconds))
            {
                continue;
            }

            return $"{match.Groups[1].Value} · {FormatElapsed(seconds)}";
        }

        return "working…";
    }

    internal static string FormatElapsed(int totalSeconds)
    {
        if (totalSeconds < 0)
        {
            totalSeconds = 0;
        }

        if (totalSeconds < 60)
        {
            return $"{totalSeconds}s";
        }

        int minutes = totalSeconds / 60;
        int seconds = totalSeconds % 60;
        if (minutes < 60)
        {
            return seconds == 0 ? $"{minutes}m" : $"{minutes}m {seconds}s";
        }

        int hours = minutes / 60;
        minutes %= 60;
        return minutes == 0 ? $"{hours}h" : $"{hours}h {minutes}m";
    }

    internal static double? TryParseLatestQualityHashPercent(IEnumerable<string> lines)
    {
        foreach (string line in lines.Reverse())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            Match match = QualityHashPercent.Match(line);
            if (!match.Success)
            {
                continue;
            }

            if (int.TryParse(match.Groups[1].Value, out int percent))
            {
                return Math.Clamp(percent, 0, 100);
            }
        }

        return null;
    }

    internal static string? TryParseLatestApplyStepCue(IEnumerable<string> lines)
    {
        foreach (string line in lines.Reverse())
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            Match match = ApplyStepIndex.Match(line);
            if (!match.Success)
            {
                continue;
            }

            return $"Step {match.Groups[1].Value} of {match.Groups[2].Value}";
        }

        return null;
    }

    private static string? TryReadFailureMessage(string workDirectory)
    {
        string path = Path.Combine(workDirectory, ServicingWorkspace.FailureFileName);
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            FailureMessageDto? dto = JsonSerializer.Deserialize<FailureMessageDto>(stream, FailureJsonOptions);
            return string.IsNullOrWhiteSpace(dto?.Message) ? null : dto.Message.Trim();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static IReadOnlyList<string> ReadSharedLogLines(string path)
    {
        using FileStream stream = new(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using StreamReader reader = new(stream);
        List<string> lines = [];
        while (reader.ReadLine() is { } line)
        {
            lines.Add(line);
        }

        return lines;
    }

    private sealed record FailureMessageDto(string? Message);

    [GeneratedRegex(@"^\S+ running \d+s$", RegexOptions.CultureInvariant)]
    private static partial Regex TrailHeartbeat();

    [GeneratedRegex(@"^(\S+) running (\d+)s$", RegexOptions.CultureInvariant)]
    private static partial Regex AliveHeartbeatRegex();

    [GeneratedRegex(@"^\s*\[.*\d+\.\d+%\s*\]", RegexOptions.CultureInvariant)]
    private static partial Regex DismProgressBar();

    [GeneratedRegex(@"quality hash (\d+)%", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex QualityHashPercentRegex();

    [GeneratedRegex(@"Apply\s+(\d+)/(\d+)", RegexOptions.CultureInvariant)]
    private static partial Regex ApplyStepIndexRegex();
}
