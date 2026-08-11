using WinMint.Wizard;

namespace WinMint.Tests;

public class FlashGuidanceTests
{
    [Fact]
    public void Format_gateB_states_wipe_media_not_primary_proven()
    {
        string text = FlashGuidance.Format(
            @"C:\work\out.iso",
            @"C:\work",
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
        string text = FlashGuidance.Format(@"D:\out.iso", @"D:\work", gateB: false);
        Assert.Contains("not the wipe gate", text, StringComparison.Ordinal);
        Assert.Contains("evidence.json", text, StringComparison.Ordinal);
    }

    [Fact]
    public void TryReadOutputIsoSha256_reads_digest()
    {
        string work = Path.Combine(Path.GetTempPath(), "winmint-flash-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(
                Path.Combine(work, "evidence.json"),
                """{"digests":{"outputIso.sha256":"deadbeef"}}""");
            Assert.Equal("deadbeef", FlashGuidance.TryReadOutputIsoSha256(work));
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }
}
