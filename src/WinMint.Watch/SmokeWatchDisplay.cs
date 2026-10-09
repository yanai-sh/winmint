using System.Globalization;

using Spectre.Console;

namespace WinMint.Watch;

internal static class SmokeWatchDisplay
{
    internal const int StatusStaleThresholdSeconds = 120;

    internal static bool IsAlarmVerdict(string verdict) =>
        string.Equals(verdict, "harness-stale", StringComparison.Ordinal)
        || string.Equals(verdict, "empty-vhd", StringComparison.Ordinal);

    internal static string VerdictSpectreColor(string verdict)
    {
        if (string.Equals(verdict, "done", StringComparison.Ordinal))
        {
            return "green";
        }

        if (IsAlarmVerdict(verdict))
        {
            return "red";
        }

        return "cyan";
    }

    internal static bool ShowStatusStaleSuffix(string verdict, int statusAgeSeconds) =>
        IsAlarmVerdict(verdict) && statusAgeSeconds > StatusStaleThresholdSeconds;

    internal static string ClipHostLine(string text, int maxWidth)
    {
        if (maxWidth < 8 || string.IsNullOrEmpty(text))
        {
            return text;
        }

        if (text.Length <= maxWidth)
        {
            return text;
        }

        return string.Concat(text.AsSpan(0, maxWidth - 1), "…");
    }

    internal static string BuildSmokeHeaderMarkup(
        string verdict,
        string phase,
        int stallLeft,
        int wallLeft,
        int statusAgeSeconds)
    {
        string displayVerdict = string.IsNullOrWhiteSpace(verdict) ? "awaiting-run" : verdict;
        string color = VerdictSpectreColor(displayVerdict);
        string phaseText = string.IsNullOrWhiteSpace(phase) ? "-" : phase;
        string line =
            $"verdict [{color}]{Markup.Escape(displayVerdict)}[/]  " +
            $"phase [cyan]{Markup.Escape(phaseText)}[/]  " +
            $"stall {stallLeft.ToString(CultureInfo.InvariantCulture)}m  " +
            $"wall {wallLeft.ToString(CultureInfo.InvariantCulture)}m";
        if (ShowStatusStaleSuffix(displayVerdict, statusAgeSeconds))
        {
            line += $"  status stale {statusAgeSeconds.ToString(CultureInfo.InvariantCulture)}s";
        }

        return line;
    }
}
