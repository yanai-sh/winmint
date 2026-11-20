using WinMint.WinPeApply;

namespace WinMint.Tests;

public class BrandLockupTests
{
    [Fact]
    public void Raster_paints_the_dark_lockup_wordmark()
    {
        const int width = 800;
        const int height = 200;
        Assert.True(
            BrandLockup.TryRasterize(width, height, out byte[] bgra),
            "Direct2D did not rasterize assets/brand/readme/dark.svg.");
        Assert.Equal(width * height * 4, bgra.Length);

        // viewBox 300 67 3048 762. WIN is the near-white gradient; the icon is #1170f2; MINT is the green-blue gradient.
        Assert.True(Has(bgra, width, height, 0.30f, 0.40f, 0.48f, 0.62f, Light), "WIN wordmark is missing.");
        Assert.True(Has(bgra, width, height, 0.06f, 0.30f, 0.22f, 0.70f, Blue), "Icon blue is missing.");
        Assert.True(Has(bgra, width, height, 0.55f, 0.35f, 0.78f, 0.65f, Mint), "MINT wordmark is missing.");
    }

    private static bool Light(byte b, byte g, byte r, byte a) => a > 200 && r > 200 && g > 200 && b > 200;

    private static bool Blue(byte b, byte g, byte r, byte a) => a > 200 && b > 180 && b > r + 40 && b > g;

    private static bool Mint(byte b, byte g, byte r, byte a) => a > 200 && g > 140 && g > r && b > 40;

    private static bool Has(
        byte[] bgra,
        int width,
        int height,
        float x0,
        float y0,
        float x1,
        float y1,
        Func<byte, byte, byte, byte, bool> match)
    {
        int left = Math.Clamp((int)(x0 * width), 0, width - 1);
        int right = Math.Clamp((int)(x1 * width), left + 1, width);
        int top = Math.Clamp((int)(y0 * height), 0, height - 1);
        int bottom = Math.Clamp((int)(y1 * height), top + 1, height);
        for (int y = top; y < bottom; y++)
        {
            int row = y * width * 4;
            for (int x = left; x < right; x++)
            {
                int i = row + (x * 4);
                if (match(bgra[i], bgra[i + 1], bgra[i + 2], bgra[i + 3]))
                {
                    return true;
                }
            }
        }

        return false;
    }
}
