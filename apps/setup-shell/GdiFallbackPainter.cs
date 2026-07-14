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

        var canvas = ParseColor(tokens.Canvas, 0x001D1611);
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

        // Logo text in the upper region
        var text = "WinMint";
        var fontSize = 24;
        var textY = (int)(height * 0.38f - fontSize);
        DrawLine(hdc, text, 0, textY, width, muted, fontSize, true);

        // Progress bar
        {
            var barW = 160;
            var barH = tokens.Layout.ProgressHeight > 0 ? (int)tokens.Layout.ProgressHeight : 3;
            var barX = (width - barW) / 2;
            var barY = (int)(height * 0.55f);

            var trackBg = NativeMethods.CreateSolidBrush(ParseColor(tokens.ProgressTrack, 0x0036302E));
            var trackRect = new NativeMethods.RECT { Left = barX, Top = barY, Right = barX + barW, Bottom = barY + barH };
            NativeMethods.FillRect(hdc, ref trackRect, trackBg);
            NativeMethods.DeleteObject(trackBg);

            var accentBrush = NativeMethods.CreateSolidBrush(accent);
            if (string.Equals(status.ProgressMode, "determinate", StringComparison.OrdinalIgnoreCase))
            {
                var pct = status.ProgressPct;
                if (pct < 0) pct = 0;
                if (pct > 100) pct = 100;
                var fillW = (int)(barW * (pct / 100.0));
                var fillRect = new NativeMethods.RECT { Left = barX, Top = barY, Right = barX + fillW, Bottom = barY + barH };
                NativeMethods.FillRect(hdc, ref fillRect, accentBrush);
            }
            else
            {
                var elapsedS = (float)(DateTime.Now.TimeOfDay.TotalSeconds);
                var cycle = (elapsedS * 0.6f) % 1.0f;
                var segW = (int)(barW * 0.25f);
                var segX = barX + (int)((barW - segW) * cycle);
                var fillRect = new NativeMethods.RECT { Left = segX, Top = barY, Right = segX + segW, Bottom = barY + barH };
                NativeMethods.FillRect(hdc, ref fillRect, accentBrush);
            }
            NativeMethods.DeleteObject(accentBrush);
        }

        // Info stack
        var groupText = !string.IsNullOrWhiteSpace(status.GroupLabel) ? status.GroupLabel.ToUpperInvariant() : "SETTING UP";
        var groupY = (int)(height * 0.59f);
        DrawLine(hdc, groupText, 0, groupY, width, muted, 11, true);

        var taskText = !string.IsNullOrWhiteSpace(status.TaskLabel) ? status.TaskLabel : "Working…";
        var taskY = groupY + 20;
        DrawLine(hdc, taskText, 0, taskY, width, ink, 14, false);

        // Steps list (centered below task)
        var stepsY = taskY + 28;
        if (status.Steps is not null && status.Steps.Count > 0)
        {
            foreach (var step in status.Steps)
            {
                if (string.Equals(step.Status, "done", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var label = step.Label;
                if (string.IsNullOrWhiteSpace(label))
                {
                    label = step.Id;
                }

                var isCurrent = string.Equals(step.Status, "current", StringComparison.OrdinalIgnoreCase);
                var stepColor = isCurrent ? ink : BlendColor(dim, canvas, 0.38f);
                DrawLine(hdc, label, 0, stepsY, width, stepColor, 11, false);
                stepsY += 16;
            }
        }

        // Heartbeat footer
        var metaText = SplashPainter.FormatShellMeta(status);
        var metaY = height - (tokens.Layout.DockPaddingBottom > 0 ? tokens.Layout.DockPaddingBottom : 88);
        DrawLine(hdc, metaText, 0, metaY, width, BlendColor(dim, canvas, 0.72f), 11, false);

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
