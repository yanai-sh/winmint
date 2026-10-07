using System.Text.RegularExpressions;

using WinMint.Orchestrator;

namespace WinMint.Wizard.ViewModels;

internal readonly record struct ApplyBuildPresentation(
    string StageLine,
    string StatusTail,
    double? ProgressPercent,
    bool IsProgressIndeterminate,
    string? StepCue)
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
        int tailLines = 20)
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
        IEnumerable<string> filtered = rawLines.Where(ShouldShowInStatusTail);
        string statusTail = string.Join(
            Environment.NewLine,
            filtered.TakeLast(Math.Max(0, tailLines)));

        bool indeterminate = progressPercent is null;
        return new ApplyBuildPresentation(
            stageLine,
            statusTail,
            progressPercent,
            indeterminate,
            stepCue);
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

    [GeneratedRegex(@"^\S+ running \d+s$", RegexOptions.CultureInvariant)]
    private static partial Regex TrailHeartbeat();

    [GeneratedRegex(@"^\s*\[.*\d+\.\d+%\s*\]", RegexOptions.CultureInvariant)]
    private static partial Regex DismProgressBar();

    [GeneratedRegex(@"quality hash (\d+)%", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex QualityHashPercentRegex();

    [GeneratedRegex(@"Apply\s+(\d+)/(\d+)", RegexOptions.CultureInvariant)]
    private static partial Regex ApplyStepIndexRegex();
}
