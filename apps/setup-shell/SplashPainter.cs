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
        var stepCount = CountVisibleSteps(status);
        var metrics = SplashLayout.Resolve(width, height, tokens.Layout, stepCount);

        renderTarget.Clear(ColorUtil.ParseHex(tokens.Canvas));

        if (heroAsset is not null)
        {
            var heroSize = heroAsset.Bitmap.Size;
            var src = heroAsset.ContentSrc;
            if (src.Width <= 0 || src.Height <= 0)
            {
                src = new Rect(0, 0, heroSize.Width, heroSize.Height);
            }

            var scale = Math.Min(metrics.HeroMaxWidth / src.Width, metrics.HeroMaxHeight / src.Height);
            var drawW = src.Width * scale;
            var drawH = src.Height * scale;
            var heroX = (width - drawW) * 0.5f;
            var brandHeight = Math.Max(0f, metrics.BrandAreaBottom - metrics.BrandAreaTop);
            if (drawH > brandHeight)
            {
                var shrink = brandHeight / drawH;
                drawW *= shrink;
                drawH = brandHeight;
            }

            var heroY = metrics.BrandAreaTop + (brandHeight - drawH) * 0.5f;
            var dest = new Rect(heroX, heroY, drawW, drawH);
            renderTarget.DrawBitmap(heroAsset.Bitmap, dest, 1f, Vortice.Direct2D1.BitmapInterpolationMode.Linear, src);
        }

        var groupText = (status.GroupLabel ?? "Setting up").ToUpperInvariant();
        var groupRect = new Rect(metrics.DockLeft, metrics.DockTop, metrics.DockWidth, metrics.GroupLineHeight);
        using (var groupBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Dim)))
        {
            renderTarget.DrawText(groupText, groupFormat, groupRect, groupBrush);
        }

        var taskTop = metrics.DockTop + metrics.GroupLineHeight + metrics.GroupToTaskGap;
        var taskRect = new Rect(metrics.DockLeft, taskTop, metrics.DockWidth, metrics.TaskLineHeight * 2f);
        using (var taskBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Ink)))
        {
            renderTarget.DrawText(status.TaskLabel ?? "Working…", taskFormat, taskRect, taskBrush);
        }

        var stepsTop = taskTop + metrics.TaskLineHeight * 2f + metrics.TaskToStepsGap;
        DrawStepList(renderTarget, tokens, status, stepFormat, metrics.DockLeft, stepsTop, metrics.DockWidth, metrics.StepLineHeight);

        var metaText = FormatShellMeta(status);
        if (!string.IsNullOrWhiteSpace(metaText))
        {
            var metaTop = stepsTop + metrics.StepCount * metrics.StepLineHeight + metrics.StepsToMetaGap;
            var metaRect = new Rect(metrics.DockLeft, metaTop, metrics.DockWidth, metrics.MetaLineHeight);
            using var metaBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Dim));
            renderTarget.DrawText(metaText, groupFormat, metaRect, metaBrush);
        }

        if (!string.IsNullOrWhiteSpace(status.Banner))
        {
            var bannerColor = status.BannerKind switch
            {
                "fail" => tokens.Fail,
                "warn" => tokens.Warn,
                _ => tokens.Muted
            };
            var bannerRect = new Rect(
                (width - metrics.BannerMaxWidth) * 0.5f,
                height - metrics.BannerOffsetBottom,
                metrics.BannerMaxWidth,
                40);
            using var bannerBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(bannerColor));
            renderTarget.DrawText(status.Banner, bannerFormat, bannerRect, bannerBrush);
        }
    }

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

            var labelLeft = left;
            var labelWidth = width;
            var isCurrent = string.Equals(step.Status, "current", StringComparison.OrdinalIgnoreCase);
            if (isCurrent)
            {
                using (var accentBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Accent, 0.48f)))
                {
                    renderTarget.FillRectangle(new Rect(left, y + 2f, 2f, Math.Max(4f, lineHeight - 4f)), accentBrush);
                }

                labelLeft = left + 10f;
                labelWidth = width - 10f;
            }

            var alpha = isCurrent ? 1f : 0.38f;
            var textColor = isCurrent ? tokens.Muted : tokens.Dim;
            var labelRect = new Rect(labelLeft, y, labelWidth, lineHeight);
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
