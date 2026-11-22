using WinMint.WinPeApply;

namespace WinMint.Tests;

public class ImageFitTests
{
    [Fact]
    public void Decide_fits_only_when_both_sizes_are_known_and_the_volume_is_large_enough()
    {
        Assert.Equal(0, ImageFit.Decide(100, 100));
        Assert.Equal(0, ImageFit.Decide(100, 101));
        Assert.Equal(2, ImageFit.Decide(101, 100));
        Assert.Equal(1, ImageFit.Decide(0, 100));
        Assert.Equal(1, ImageFit.Decide(100, 0));
    }

    [Fact]
    public void TryParseDismSize_reads_the_byte_count()
    {
        const string text = "Index : 1\r\nSize : 16,234,567,890 bytes\r\n";
        Assert.True(ImageFit.TryParseDismSize(text, out long bytes));
        Assert.Equal(16_234_567_890, bytes);
    }

    [Fact]
    public void LastStatusLine_keeps_the_last_nonempty_line()
    {
        Assert.Equal("Unplug the USB, then turn the laptop on.", ApplyBootSplash.LastStatusLine("Applying Windows.\r\n\r\nUnplug the USB, then turn the laptop on.\r\n"));
        Assert.Equal("", ApplyBootSplash.LastStatusLine("  \r\n"));
    }
}
