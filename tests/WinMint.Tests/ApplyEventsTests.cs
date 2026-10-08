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
}
