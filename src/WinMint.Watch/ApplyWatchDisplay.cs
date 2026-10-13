using Spectre.Console;

using WinMint.Orchestrator;

namespace WinMint.Watch;

/// <summary>Pure cell mapping for Spectre apply-event table rows (no Live / console).</summary>
internal static class ApplyWatchDisplay
{
    internal static (string Time, string Opcode, string Outcome, string Summary) Cells(
        ApplyEvent ev,
        int summaryWidth = 60) =>
        (
            ApplyEvents.DisplayTime(ev),
            ApplyEvents.DisplayOpcode(ev),
            ApplyEvents.DisplayOutcome(ev),
            ApplyEvents.DisplaySummary(ev, summaryWidth));

    internal static Markup ColorOutcome(string outcome)
    {
        if (string.Equals(outcome, "ok", StringComparison.OrdinalIgnoreCase))
        {
            return new Markup($"[green]{Markup.Escape(outcome)}[/]");
        }

        if (string.Equals(outcome, "fail", StringComparison.OrdinalIgnoreCase))
        {
            return new Markup($"[red]{Markup.Escape(outcome)}[/]");
        }

        return new Markup(Markup.Escape(outcome));
    }
}
