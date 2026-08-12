using WinMint.Wizard;

namespace WinMint.Tests;

public class FlashGuidanceTests
{
    [Fact]
    public void Format_gateB_states_wipe_media_not_primary_proven()
    {
        string text = FlashGuidance.Format(
            @"C:\work\out.iso",
            gateB: true,
            outputIsoSha256: "abc123");

        Assert.Contains("Gate B wipe media ready", text, StringComparison.Ordinal);
        Assert.Contains("not a completed Primary install", text, StringComparison.Ordinal);
        Assert.Contains("Rufus", text, StringComparison.Ordinal);
        Assert.Contains("DD Image", text, StringComparison.Ordinal);
        Assert.Contains("abc123", text, StringComparison.Ordinal);
        Assert.Contains(@"C:\work\out.iso", text, StringComparison.Ordinal);
    }

    [Fact]
    public void Format_test_lane_is_not_wipe_gate()
    {
        string text = FlashGuidance.Format(@"D:\out.iso", gateB: false);
        Assert.Contains("not the wipe gate", text, StringComparison.Ordinal);
        Assert.Contains("evidence.json", text, StringComparison.Ordinal);
    }

    [Fact]
    public void Format_without_sha_points_at_evidence()
    {
        string text = FlashGuidance.Format(@"E:\iso.iso", gateB: true);
        Assert.DoesNotContain("SHA-256 (digests.outputIso.sha256):", text, StringComparison.Ordinal);
        Assert.Contains("digests.outputIso.sha256", text, StringComparison.Ordinal);
    }
}
