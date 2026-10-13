using WinMint.Orchestrator;
using WinMint.Watch;

namespace WinMint.Tests;

public class ApplyWatchDisplayTests
{
    [Fact]
    public void Cells_maps_long_opcode_without_string_split()
    {
        ApplyEvent ev = new(
            Ts: "2026-10-08T10:01:00Z",
            Kind: "opcode.end",
            Opcode: "StampOfflineDefaultUser",
            Outcome: "ok",
            Summary: "StampOfflineDefaultUser ok (1.2s)");

        (string time, string opcode, string outcome, string summary) = ApplyWatchDisplay.Cells(ev, summaryWidth: 40);

        Assert.False(string.IsNullOrWhiteSpace(time));
        Assert.Equal("StampOfflineDefaultUser", opcode);
        Assert.Equal(23, opcode.Length);
        Assert.Equal("ok", outcome);
        Assert.Equal("ok (1.2s)", summary);
    }

    [Fact]
    public void Cells_run_start_uses_kind_and_dash_outcome()
    {
        ApplyEvent ev = new(Ts: "2026-10-08T10:00:00Z", Kind: "run.start", Summary: "Apply start");
        (string _, string opcode, string outcome, string summary) = ApplyWatchDisplay.Cells(ev);

        Assert.Equal("run.start", opcode);
        Assert.Equal("-", outcome);
        Assert.Equal("Apply start", summary);
    }

    [Fact]
    public void ColorOutcome_returns_markup_for_ok_fail_and_dash()
    {
        Assert.NotNull(ApplyWatchDisplay.ColorOutcome("ok"));
        Assert.NotNull(ApplyWatchDisplay.ColorOutcome("fail"));
        Assert.NotNull(ApplyWatchDisplay.ColorOutcome("-"));
    }
}
