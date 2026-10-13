using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ApplyEventsTests
{
    [Fact]
    public void ReadTail_formats_opcode_end_and_proof_percent()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-events-" + Guid.NewGuid().ToString("N") + ".jsonl");
        try
        {
            File.WriteAllText(
                path,
                """
                {"ts":"2026-10-08T10:00:00Z","kind":"run.start","summary":"Apply start"}
                {"ts":"2026-10-08T10:01:00Z","kind":"opcode.end","opcode":"AddQualityUpdates","index":2,"count":4,"outcome":"ok","durationMs":1000,"summary":"AddQualityUpdates ok (1.0s)"}
                {"ts":"2026-10-08T10:00:30Z","kind":"proof","opcode":"AddQualityUpdates","label":"quality-hash","percent":42,"summary":"quality hash 42%"}
                """);

            IReadOnlyList<ApplyEvent> events = ApplyEvents.ReadTail(path);
            Assert.Equal(3, events.Count);
            Assert.Equal(42, ApplyEvents.TryLatestProofPercent(events));
            Assert.Equal("Step 2 of 4", ApplyEvents.TryLatestStepCue(events));
            string row = ApplyEvents.FormatRow(events[1], summaryWidth: 40);
            Assert.Contains("AddQualityUpdates", row, StringComparison.Ordinal);
            Assert.Contains("ok", row, StringComparison.Ordinal);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void FormatRow_long_opcode_keeps_outcome_ok()
    {
        ApplyEvent ev = new(
            Ts: "2026-10-08T10:01:00Z",
            Kind: "opcode.end",
            Opcode: "DisableOptionalFeatures",
            Outcome: "ok",
            Summary: "DisableOptionalFeatures ok (12.0s)");

        Assert.Equal(23, ev.Opcode!.Length);
        string row = ApplyEvents.FormatRow(ev, summaryWidth: 40);
        Assert.Contains("DisableOptionalFeatures", row, StringComparison.Ordinal);
        Assert.Contains("  ok  ", row, StringComparison.Ordinal);
        Assert.Equal("ok", ApplyEvents.DisplayOutcome(ev));
        Assert.Equal("ok (12.0s)", ApplyEvents.DisplaySummary(ev, 40));
    }

    [Fact]
    public void ForDisplay_coalesces_proofs_to_latest_per_label()
    {
        ApplyEvent[] events =
        [
            new(Kind: "run.start", Summary: "Apply start"),
            new(Kind: "proof", Opcode: "AddQualityUpdates", Label: "quality-hash", Percent: 0, Summary: "quality hash 0%"),
            new(Kind: "proof", Opcode: "AddQualityUpdates", Label: "quality-hash", Percent: 50, Summary: "quality hash 50%"),
            new(Kind: "proof", Opcode: "AddQualityUpdates", Label: "quality-hash", Percent: 100, Summary: "quality hash 100%"),
            new(Kind: "opcode.end", Opcode: "AddQualityUpdates", Outcome: "ok", Summary: "AddQualityUpdates ok (1.0s)"),
        ];

        IReadOnlyList<ApplyEvent> display = ApplyEvents.ForDisplay(events);
        Assert.Equal(3, display.Count);
        Assert.Equal(1, display.Count(e => string.Equals(e.Kind, "proof", StringComparison.Ordinal)));
        Assert.Equal(100, display.Single(e => e.Kind == "proof").Percent);
        Assert.Equal(100, ApplyEvents.TryLatestProofPercent(events));

        IReadOnlyList<string> rows = ApplyEvents.FormatRows(events);
        Assert.Equal(3, rows.Count);
        Assert.Single(rows, r => r.Contains("quality hash", StringComparison.Ordinal));
    }

    [Fact]
    public void ForDisplay_retains_opcode_history_when_proofs_would_dominate_raw_tail()
    {
        List<ApplyEvent> events = [];
        for (int i = 0; i < 20; i++)
        {
            events.Add(new(Kind: "opcode.end", Opcode: $"Stage{i}", Outcome: "ok", Summary: $"Stage{i} ok"));
        }

        for (int p = 0; p < 30; p++)
        {
            events.Add(new(
                Kind: "proof",
                Opcode: "AddQualityUpdates",
                Label: "quality-hash",
                Percent: p,
                Summary: $"quality hash {p}%"));
        }

        Assert.DoesNotContain(events.TakeLast(40), e => e.Opcode == "Stage0");

        IReadOnlyList<ApplyEvent> display = ApplyEvents.ForDisplay(events, maxRows: 40);
        Assert.Contains(display, e => e.Opcode == "Stage0");
        Assert.Equal(1, display.Count(e => string.Equals(e.Kind, "proof", StringComparison.Ordinal)));
        Assert.Equal(29, display.Single(e => e.Kind == "proof").Percent);
        Assert.Equal(21, display.Count);
    }
}
