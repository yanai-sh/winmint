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

        var visibleCount = CountVisibleSteps(status);
        var metrics = SplashLayout.Resolve(width, height, tokens.Layout, visibleCount);
        var dockLeft = (int)metrics.DockLeft;
        var dockWidth = (int)metrics.DockWidth;
        var groupTop = (int)metrics.DockTop;
        var taskTop = groupTop + (int)(metrics.GroupLineHeight + metrics.GroupToTaskGap);
        var stepsTop = taskTop + (int)(metrics.TaskLineHeight * 2f + metrics.TaskToStepsGap);

        NativeMethods.SetBkMode(hdc, NativeMethods.TRANSPARENT);
        DrawLine(hdc, status.GroupLabel, dockLeft, groupTop, dockWidth, BlendColor(dim, canvas, 0.88f), 11, true);
        DrawLine(hdc, status.TaskLabel, dockLeft, taskTop, dockWidth, ink, 15, false);

        if (status.Steps is not null)
        {
            var y = stepsTop;
            foreach (var step in status.Steps)
            {
                if (string.Equals(step.Status, "done", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var labelLeft = dockLeft;
                var labelWidth = dockWidth;
                var isCurrent = string.Equals(step.Status, "current", StringComparison.OrdinalIgnoreCase);
                if (isCurrent)
                {
                    var bar = new NativeMethods.RECT
                    {
                        Left = dockLeft,
                        Top = y + 2,
                        Right = dockLeft + 2,
                        Bottom = y + Math.Max(6, (int)metrics.StepLineHeight - 2)
                    };
                    var barBrush = NativeMethods.CreateSolidBrush(BlendColor(accent, canvas, 0.48f));
                    NativeMethods.FillRect(hdc, ref bar, barBrush);
                    NativeMethods.DeleteObject(barBrush);
                    labelLeft = dockLeft + 10;
                    labelWidth = dockWidth - 10;
                }

                var textColor = isCurrent ? muted : BlendColor(dim, canvas, 0.38f);
                var label = string.IsNullOrWhiteSpace(step.Label) ? step.Id : step.Label;
                DrawLine(hdc, label, labelLeft, y, labelWidth, textColor, 11, false);
                y += (int)metrics.StepLineHeight;
            }
        }

        var metaText = SplashPainter.FormatShellMeta(status);
        if (!string.IsNullOrWhiteSpace(metaText))
        {
            var metaTop = stepsTop + (int)(metrics.StepCount * metrics.StepLineHeight + metrics.StepsToMetaGap);
            DrawLine(hdc, metaText, dockLeft, metaTop, dockWidth, BlendColor(dim, canvas, 0.72f), 11, false);
        }

        if (!string.IsNullOrWhiteSpace(status.Banner))
        {
            var bannerColor = status.BannerKind switch
            {
                "fail" => fail,
                "warn" => warn,
                _ => muted
            };
            var bannerTop = Math.Max(24, height - (int)metrics.BannerOffsetBottom);
            DrawLine(hdc, status.Banner, dockLeft, bannerTop, dockWidth, bannerColor, 13, false);
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
        NativeMethods.DrawTextW(hdc, text, text.Length, ref rect, NativeMethods.DT_LEFT | NativeMethods.DT_TOP | NativeMethods.DT_WORDBREAK | NativeMethods.DT_NOPREFIX);
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
