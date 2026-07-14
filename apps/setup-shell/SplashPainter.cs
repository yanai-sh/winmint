using System.Drawing;
using System.Runtime.InteropServices;
using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using Vortice.WIC;

namespace WinMintSetupShell;

internal static class SplashPainter
{
    private static readonly System.Diagnostics.Stopwatch _animationStopwatch = System.Diagnostics.Stopwatch.StartNew();
    public static HeroAsset? LoadHeroBitmap(ID2D1RenderTarget renderTarget, string shellRoot, ShellLogger? logger)
    {
        var heroPath = Path.Combine(shellRoot, "winmint_hero_ui.png");
        if (!File.Exists(heroPath))
        {
            heroPath = Path.Combine(shellRoot, "winmint_hero.png");
        }
        if (!File.Exists(heroPath))
        {
            logger?.Info($"hero image missing in {shellRoot}");
            return null;
        }

        try
        {
            using var wicImagingFactory = new IWICImagingFactory();
            using var decoder = wicImagingFactory.CreateDecoderFromFileName(heroPath);
            using var frame = decoder.GetFrame(0);
            frame.GetSize(out var frameWidth, out var frameHeight);
            using var converter = wicImagingFactory.CreateFormatConverter();
            converter.Initialize(frame, Vortice.WIC.PixelFormat.Format32bppPBGRA);
            var contentSrc = ComputeOpaqueBounds(wicImagingFactory, converter, (int)frameWidth, (int)frameHeight);
            var props = new BitmapProperties(
                new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
                96f,
                96f);
            var bitmap = renderTarget.CreateBitmapFromWicBitmap(converter, props);
            var size = bitmap.Size;
            logger?.Info(
                $"hero loaded from {heroPath} ({size.Width}x{size.Height}, content {contentSrc.Width:0}x{contentSrc.Height:0}@{contentSrc.X:0},{contentSrc.Y:0})");
            return new HeroAsset(bitmap, contentSrc);
        }
        catch (Exception ex)
        {
            logger?.Info($"hero load warning: {ex.Message}");
            return null;
        }
    }

    private static Rect ComputeOpaqueBounds(IWICImagingFactory factory, IWICFormatConverter converter, int width, int height)
    {
        using var bitmap = factory.CreateBitmapFromSource(converter, BitmapCreateCacheOption.CacheOnLoad);
        using var bitmapLock = bitmap.Lock(new Rectangle(0, 0, width, height), BitmapLockFlags.Read);
        bitmapLock.GetSize(out var lockWidth, out var lockHeight);
        var stride = (int)bitmapLock.Stride;
        var pixels = new byte[stride * (int)lockHeight];
        var region = bitmapLock.Data;
        if (region.DataPointer == IntPtr.Zero)
        {
            return new Rect(0, 0, width, height);
        }

        for (var y = 0; y < (int)lockHeight; y++)
        {
            var row = IntPtr.Add(region.DataPointer, y * (int)region.Pitch);
            Marshal.Copy(row, pixels, y * stride, Math.Min(stride, (int)lockWidth * 4));
        }

        var minX = width;
        var minY = height;
        var maxX = -1;
        var maxY = -1;
        for (var y = 0; y < (int)lockHeight; y++)
        {
            var row = y * stride;
            for (var x = 0; x < (int)lockWidth; x++)
            {
                if (pixels[row + x * 4 + 3] > 12)
                {
                    minX = Math.Min(minX, x);
                    minY = Math.Min(minY, y);
                    maxX = Math.Max(maxX, x);
                    maxY = Math.Max(maxY, y);
                }
            }
        }

        if (maxX < 0)
        {
            return new Rect(0, 0, width, height);
        }

        return new Rect(minX, minY, maxX - minX + 1, maxY - minY + 1);
    }

    public static void Paint(
        ID2D1RenderTarget renderTarget,
        int width,
        int height,
        DesignTokens tokens,
        SetupShellStatus status,
        HeroAsset? heroAsset,
        IDWriteTextFormat groupFormat,
        IDWriteTextFormat taskFormat,
        IDWriteTextFormat stepFormat,
        IDWriteTextFormat bannerFormat)
    {
        var elapsedS = _animationStopwatch.ElapsedMilliseconds / 1000f;
        var metrics = SplashLayout.Resolve(width, height, tokens.Layout, status.Steps?.Count ?? 0);

        renderTarget.Clear(ColorUtil.ParseHex(tokens.Canvas));

        if (heroAsset is not null)
        {
            var heroSize = heroAsset.Bitmap.Size;
            var src = heroAsset.ContentSrc;
            if (src.Width <= 0 || src.Height <= 0)
            {
                src = new Rect(0, 0, heroSize.Width, heroSize.Height);
            }

            var pulse = 1.0f + 0.02f * (float)Math.Sin(elapsedS * 2.0f);
            var logoSize = Clamp(height * 0.12f, 96f, 192f) * pulse;
            var scale = Math.Min(logoSize / src.Width, logoSize / src.Height);
            var logoW = src.Width * scale;
            var logoH = src.Height * scale;

            var logoX = (width - logoW) * 0.5f;
            var logoY = (height - logoH) * 0.38f;

            var dest = new Rect(logoX, logoY, logoW, logoH);
            renderTarget.DrawBitmap(heroAsset.Bitmap, dest, 1f, Vortice.Direct2D1.BitmapInterpolationMode.Linear, src);
        }

        // Progress bar
        {
            var barW = 160f;
            var barH = tokens.Layout.ProgressHeight > 0 ? tokens.Layout.ProgressHeight : 3f;
            var barX = (width - barW) * 0.5f;
            var barY = height * 0.55f;

            using (var trackBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.ProgressTrack)))
            {
                renderTarget.FillRectangle(new Rect(barX, barY, barW, barH), trackBrush);
            }

            using (var accentBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Accent)))
            {
                if (string.Equals(status.ProgressMode, "determinate", StringComparison.OrdinalIgnoreCase))
                {
                    var pct = (float)Clamp((float)status.ProgressPct, 0f, 100f);
                    var fillW = barW * (pct / 100f);
                    renderTarget.FillRectangle(new Rect(barX, barY, fillW, barH), accentBrush);
                }
                else
                {
                    var cycle = (elapsedS * 0.6f) % 1.0f;
                    var segW = barW * 0.25f;
                    var segX = barX + (barW - segW) * cycle;
                    renderTarget.FillRectangle(new Rect(segX, barY, segW, barH), accentBrush);
                }
            }
        }

        // Info stack
        var groupY = height * 0.59f;
        var groupText = !string.IsNullOrWhiteSpace(status.GroupLabel) ? status.GroupLabel.ToUpperInvariant() : "SETTING UP";
        var groupRect = new Rect((width - metrics.DockWidth) * 0.5f, groupY, metrics.DockWidth, metrics.GroupLineHeight * 2f);
        using (var groupBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Muted)))
        {
            renderTarget.DrawText(groupText, groupFormat, groupRect, groupBrush);
        }

        var taskY = groupY + metrics.GroupLineHeight + metrics.GroupToTaskGap;
        var taskText = !string.IsNullOrWhiteSpace(status.TaskLabel) ? status.TaskLabel : "Working…";
        var taskRect = new Rect((width - metrics.DockWidth) * 0.5f, taskY, metrics.DockWidth, metrics.TaskLineHeight * 3f);
        using (var taskBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Ink)))
        {
            renderTarget.DrawText(taskText, taskFormat, taskRect, taskBrush);
        }

        var stepsY = taskY + (metrics.TaskLineHeight * 1.5f) + metrics.TaskToStepsGap;
        DrawStepList(
            renderTarget,
            tokens,
            status,
            stepFormat,
            (width - metrics.DockWidth) * 0.5f,
            stepsY,
            metrics.DockWidth,
            metrics.StepLineHeight);

        // Heartbeat footer
        var metaText = FormatShellMeta(status);
        var metaY = height - tokens.Layout.DockPaddingBottom;
        var metaRect = new Rect((width - metrics.DockWidth) * 0.5f, metaY, metrics.DockWidth, metrics.MetaLineHeight * 2f);
        using (var metaBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Dim, 0.72f)))
        {
            renderTarget.DrawText(metaText, bannerFormat, metaRect, metaBrush);
        }

        if (!string.IsNullOrWhiteSpace(status.Banner))
        {
            var bannerColor = status.BannerKind switch
            {
                "fail" => tokens.Fail,
                "warn" => tokens.Warn,
                _ => tokens.Muted
            };
            var bannerMaxWidth = Math.Min(420f, width * 0.90f);
            var bannerOffsetBottom = Clamp(height * 0.08f, 48f, 72f);
            var bannerRect = new Rect(
                (width - bannerMaxWidth) * 0.5f,
                height - bannerOffsetBottom,
                bannerMaxWidth,
                40);
            using var bannerBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(bannerColor));
            renderTarget.DrawText(status.Banner, bannerFormat, bannerRect, bannerBrush);
        }
    }

    private static float Clamp(float value, float min, float max) => Math.Max(min, Math.Min(max, value));

    public static void SaveWicBitmapPng(IWICBitmap wicBitmap, string outputPath)
    {
        var dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        var size = wicBitmap.Size;
        using var bitmapLock = wicBitmap.Lock(new Rectangle(0, 0, size.Width, size.Height), BitmapLockFlags.Read);
        bitmapLock.GetSize(out var width, out var height);
        var stride = (int)bitmapLock.Stride;
        var pixels = new byte[stride * (int)height];
        var region = bitmapLock.Data;
        if (region.DataPointer == IntPtr.Zero)
        {
            throw new InvalidOperationException("WIC bitmap lock returned a null data pointer.");
        }

        for (var y = 0; y < (int)height; y++)
        {
            var row = IntPtr.Add(region.DataPointer, y * (int)region.Pitch);
            Marshal.Copy(row, pixels, y * stride, Math.Min(stride, (int)width * 4));
        }

        var nonZero = 0;
        foreach (var value in pixels)
        {
            if (value != 0)
            {
                nonZero++;
            }
        }
        if (nonZero < 1024)
        {
            throw new InvalidOperationException($"WIC bitmap looks blank after render ({nonZero} non-zero bytes).");
        }

        GuestScreenCapture.WritePngBgra32(outputPath, pixels, (int)width, (int)height, stride);
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

    private static void DrawStepList(
        ID2D1RenderTarget renderTarget,
        DesignTokens tokens,
        SetupShellStatus status,
        IDWriteTextFormat stepFormat,
        float left,
        float top,
        float width,
        float lineHeight)
    {
        if (status.Steps is null || status.Steps.Count == 0)
        {
            return;
        }

        var y = top;
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
            var alpha = isCurrent ? 1f : 0.38f;
            var textColor = isCurrent ? tokens.Ink : tokens.Dim;
            var labelRect = new Rect(left, y, width, lineHeight);
            using (var textBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(textColor, alpha)))
            {
                renderTarget.DrawText(label, stepFormat, labelRect, textBrush);
            }

            y += lineHeight;
        }
    }

    internal static string FormatShellMeta(SetupShellStatus status)
    {
        var elapsed = TimeSpan.FromMilliseconds(Math.Max(0, status.ElapsedMs));
        var profile = string.IsNullOrWhiteSpace(status.ProfileName) ? "WinMint" : status.ProfileName;
        return $"{profile} · {(int)elapsed.TotalMinutes}:{elapsed.Seconds:D2} elapsed";
    }
}
