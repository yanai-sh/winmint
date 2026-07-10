namespace WinMintSetupShell;

internal static class GdiFallbackPainter
{
    public static void Paint(
        nint hdc,
        int width,
        int height,
        DesignTokens tokens,
        SetupShellStatus status)
    {
        if (hdc == nint.Zero || width <= 0 || height <= 0)
        {
            return;
        }

        var canvas = ParseColor("#000000", 0x00000000);
        var ink = ParseColor(tokens.Ink, 0x00FBF7F4);
        var muted = ParseColor(tokens.Muted, 0x00CCC0B7);
        var dim = ParseColor(tokens.Dim, 0x00A19287);
        var accent = ParseColor(tokens.Accent, 0x00C06700);
        var fail = ParseColor(tokens.Fail, 0x00575FFF);
        var warn = ParseColor(tokens.Warn, 0x005FC0F0);

        var full = new NativeMethods.RECT { Left = 0, Top = 0, Right = width, Bottom = height };
        var bg = NativeMethods.CreateSolidBrush(canvas);
        NativeMethods.FillRect(hdc, ref full, bg);
        NativeMethods.DeleteObject(bg);

        NativeMethods.SetBkMode(hdc, NativeMethods.TRANSPARENT);
        var text = "WinMint";
        var fontSize = 24;
        var textY = (int)(height * 0.45f - fontSize);
        DrawLine(hdc, text, 0, textY, width, muted, fontSize, true);

        if (!string.IsNullOrWhiteSpace(status.Banner))
        {
            var bannerColor = status.BannerKind switch
            {
                "fail" => fail,
                "warn" => warn,
                _ => muted
            };
            var bannerOffsetBottom = (int)Math.Max(48, height * 0.08f);
            var bannerTop = Math.Max(24, height - bannerOffsetBottom);
            DrawLine(hdc, status.Banner, 0, bannerTop, width, bannerColor, 13, false);
        }
    }

    private static int CountVisibleSteps(SetupShellStatus status)
    {
        if (status.Steps is null || status.Steps.Count == 0)
        {
            return 0;
        }

        var count = 0;
        foreach (var step in status.Steps)
        {
            if (!string.Equals(step.Status, "done", StringComparison.OrdinalIgnoreCase))
            {
                count++;
            }
        }

        return count;
    }

    private static int BlendColor(int fg, int bg, float amount)
    {
        var fr = fg & 0xFF;
        var fgG = (fg >> 8) & 0xFF;
        var fb = (fg >> 16) & 0xFF;
        var br = bg & 0xFF;
        var bgG = (bg >> 8) & 0xFF;
        var bb = (bg >> 16) & 0xFF;
        var r = (int)(fr * amount + br * (1f - amount));
        var g = (int)(fgG * amount + bgG * (1f - amount));
        var b = (int)(fb * amount + bb * (1f - amount));
        return r | (g << 8) | (b << 16);
    }

    private static void DrawLine(
        nint hdc, string text, int x, int y, int maxWidth, int color, int heightPx, bool semiBold)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        NativeMethods.SetTextColor(hdc, color);
        var font = NativeMethods.CreateFontW(
            -heightPx, 0, 0, 0,
            semiBold ? NativeMethods.FW_SEMIBOLD : NativeMethods.FW_NORMAL,
            0, 0, 0,
            NativeMethods.DEFAULT_CHARSET,
            NativeMethods.OUT_DEFAULT_PRECIS,
            NativeMethods.CLIP_DEFAULT_PRECIS,
            NativeMethods.CLEARTYPE_QUALITY,
            NativeMethods.DEFAULT_PITCH,
            "Segoe UI");
        var old = NativeMethods.SelectObject(hdc, font);
        var rect = new NativeMethods.RECT { Left = x, Top = y, Right = x + maxWidth, Bottom = y + heightPx * 4 };
        NativeMethods.DrawTextW(hdc, text, text.Length, ref rect, NativeMethods.DT_CENTER | NativeMethods.DT_TOP | NativeMethods.DT_WORDBREAK | NativeMethods.DT_NOPREFIX);
        NativeMethods.SelectObject(hdc, old);
        NativeMethods.DeleteObject(font);
    }

    private static int ParseColor(string hex, int fallback)
    {
        if (string.IsNullOrWhiteSpace(hex) || !hex.StartsWith('#') || hex.Length < 7)
        {
            return fallback;
        }

        try
        {
            var r = Convert.ToInt32(hex.Substring(1, 2), 16);
            var g = Convert.ToInt32(hex.Substring(3, 2), 16);
            var b = Convert.ToInt32(hex.Substring(5, 2), 16);
            return r | (g << 8) | (b << 16);
        }
        catch
        {
            return fallback;
        }
    }
}
