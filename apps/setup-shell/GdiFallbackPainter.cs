namespace WinMintSetupShell;

internal static class GdiFallbackPainter
{
    public static void Paint(
        nint hdc,
        int width,
        int height,
        DesignTokens tokens,
        SetupShellStatus status,
        bool stalled = false)
    {
        if (hdc == nint.Zero || width <= 0 || height <= 0)
        {
            return;
        }

        var canvas = ParseColor(tokens.Canvas, 0x001D1611);
        var ink = ParseColor(tokens.Ink, 0x00FBF7F4);
        var muted = ParseColor(tokens.Muted, 0x00CCC0B7);
        var dim = ParseColor(tokens.Dim, 0x00A19287);
        var fill = ParseColor(
            string.IsNullOrWhiteSpace(tokens.ProgressFill) ? tokens.Accent : tokens.ProgressFill,
            0x00F5EFEB);
        var fail = ParseColor(tokens.Fail, 0x00575FFF);
        var warn = ParseColor(tokens.Warn, 0x005FC0F0);

        var full = new NativeMethods.RECT { Left = 0, Top = 0, Right = width, Bottom = height };
        var bg = NativeMethods.CreateSolidBrush(canvas);
        NativeMethods.FillRect(hdc, ref full, bg);
        NativeMethods.DeleteObject(bg);
        NativeMethods.SetBkMode(hdc, NativeMethods.TRANSPARENT);

        var paint = SplashPainterOverlay.Resolve(status, stalled);

        DrawLine(hdc, "WinMint", 0, (int)(height * 0.34f), width, muted, 22, true);

        var stackY = (int)(height * 0.52f);
        DrawLine(hdc, paint.TaskLabel, 0, stackY, width, ink, 18, false);
        var cursorY = stackY + 28;
        if (!string.IsNullOrWhiteSpace(paint.DetailLabel))
        {
            DrawLine(hdc, paint.DetailLabel, 0, cursorY, width, muted, 15, false);
            cursorY += 24;
        }

        if (paint.ItemTotal > 0 && !paint.IsAlert && !paint.IsTerminal)
        {
            DrawLine(hdc, $"{Math.Max(1, paint.ItemIndex)} of {paint.ItemTotal}", 0, cursorY, width, dim, 13, false);
            cursorY += 22;
        }

        if (!paint.IsAlert)
        {
            var barW = (int)Math.Clamp(width * 0.28f, 260f, 360f);
            var barH = tokens.Layout.ProgressHeight > 0 ? (int)tokens.Layout.ProgressHeight : 3;
            var barX = (width - barW) / 2;
            var barY = Math.Max(cursorY + 8, (int)(height * 0.62f));
            var trackBg = NativeMethods.CreateSolidBrush(ParseColor(tokens.ProgressTrack, 0x0036302E));
            var trackRect = new NativeMethods.RECT { Left = barX, Top = barY, Right = barX + barW, Bottom = barY + barH };
            NativeMethods.FillRect(hdc, ref trackRect, trackBg);
            NativeMethods.DeleteObject(trackBg);

            var fillBrush = NativeMethods.CreateSolidBrush(fill);
            if (string.Equals(paint.ProgressMode, "determinate", StringComparison.OrdinalIgnoreCase))
            {
                var pct = ProgressFillAnimator.Resolve(paint.ProgressPct, paint.ProgressMode);
                var fillW = (int)(barW * (pct / 100.0));
                if (fillW > 0)
                {
                    var fillRect = new NativeMethods.RECT { Left = barX, Top = barY, Right = barX + fillW, Bottom = barY + barH };
                    NativeMethods.FillRect(hdc, ref fillRect, fillBrush);
                }
            }
            else
            {
                var elapsedS = (float)DateTime.Now.TimeOfDay.TotalSeconds;
                var cycle = (elapsedS * 0.55f) % 1.0f;
                var segW = (int)(barW * 0.28f);
                var segX = barX + (int)((barW - segW) * cycle);
                var fillRect = new NativeMethods.RECT { Left = segX, Top = barY, Right = segX + segW, Bottom = barY + barH };
                NativeMethods.FillRect(hdc, ref fillRect, fillBrush);
            }

            NativeMethods.DeleteObject(fillBrush);
        }

        if (!string.IsNullOrWhiteSpace(paint.RecoveryLine))
        {
            var bannerColor = paint.BannerKind switch
            {
                "fail" => fail,
                "warn" => warn,
                _ => muted
            };
            var bannerTop = Math.Max(24, height - (int)Math.Max(64, height * 0.12f));
            DrawLine(hdc, paint.RecoveryLine.Replace('\n', ' '), 0, bannerTop, width, bannerColor, 13, false);
        }
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
        var rect = new NativeMethods.RECT { Left = x, Top = y, Right = x + maxWidth, Bottom = y + heightPx * 5 };
        NativeMethods.DrawTextW(
            hdc,
            text,
            text.Length,
            ref rect,
            NativeMethods.DT_CENTER | NativeMethods.DT_TOP | NativeMethods.DT_WORDBREAK | NativeMethods.DT_NOPREFIX);
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

/// <summary>Shared overlay resolution for D2D/GDI painters (stall/fail/reboot).</summary>
internal static class SplashPainterOverlay
{
    public static OverlayModel Resolve(SetupShellStatus status, bool stalled)
    {
        var phase = status.Phase ?? "running";
        var isTerminal = phase is "complete" or "failed" or "reboot";
        var isFail = phase is "failed" || string.Equals(status.BannerKind, "fail", StringComparison.OrdinalIgnoreCase);
        var isReboot = phase is "reboot";

        if (isFail)
        {
            var detail = string.IsNullOrWhiteSpace(status.DetailLabel)
                ? "Your desktop will unlock. You can continue and retry later."
                : status.DetailLabel;
            var recovery = string.IsNullOrWhiteSpace(status.LogDir)
                ? detail
                : $"{detail}  Logs: {status.LogDir}";
            return new OverlayModel(
                string.IsNullOrWhiteSpace(status.TaskLabel) ? "Something went wrong" : status.TaskLabel,
                detail,
                0,
                0,
                0,
                "indeterminate",
                "fail",
                recovery,
                IsAlert: true,
                IsTerminal: true);
        }

        if (isReboot)
        {
            var detail = string.IsNullOrWhiteSpace(status.DetailLabel)
                ? "Setup will continue after restart"
                : status.DetailLabel;
            return new OverlayModel(
                string.IsNullOrWhiteSpace(status.TaskLabel) ? "Restart required" : status.TaskLabel,
                detail,
                0,
                0,
                status.ProgressPct,
                "indeterminate",
                "warn",
                detail,
                IsAlert: true,
                IsTerminal: true);
        }

        if (stalled && !isTerminal)
        {
            var recovery = string.IsNullOrWhiteSpace(status.LogDir)
                ? "This is taking longer than usual."
                : $"This is taking longer than usual.  Logs: {status.LogDir}";
            return new OverlayModel(
                "Still working",
                string.IsNullOrWhiteSpace(status.DetailLabel) ? status.TaskLabel : status.DetailLabel,
                status.ItemIndex,
                status.ItemTotal,
                status.ProgressPct,
                "indeterminate",
                "warn",
                recovery,
                IsAlert: false,
                IsTerminal: false);
        }

        return new OverlayModel(
            string.IsNullOrWhiteSpace(status.TaskLabel) ? "Getting things ready" : status.TaskLabel,
            status.DetailLabel ?? "",
            status.ItemIndex,
            status.ItemTotal,
            status.ProgressPct,
            status.ProgressMode ?? "indeterminate",
            status.BannerKind ?? "",
            "",
            IsAlert: false,
            IsTerminal: phase is "complete");
    }

    internal readonly record struct OverlayModel(
        string TaskLabel,
        string DetailLabel,
        int ItemIndex,
        int ItemTotal,
        double ProgressPct,
        string ProgressMode,
        string BannerKind,
        string RecoveryLine,
        bool IsAlert,
        bool IsTerminal);
}
