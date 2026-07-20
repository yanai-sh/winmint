using System.Drawing;
using System.Numerics;
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
        IDWriteTextFormat taskFormat,
        IDWriteTextFormat detailFormat,
        IDWriteTextFormat itemFormat,
        IDWriteTextFormat bannerFormat,
        bool stalled = false)
    {
        var elapsedS = _animationStopwatch.ElapsedMilliseconds / 1000f;
        var metrics = SplashLayout.Resolve(width, height, tokens.Layout);
        var overlay = SplashPainterOverlay.Resolve(status, stalled);
        var paint = new PaintModel(
            overlay.TaskLabel,
            overlay.DetailLabel,
            overlay.ItemIndex,
            overlay.ItemTotal,
            overlay.ProgressPct,
            overlay.ProgressMode,
            overlay.BannerKind,
            overlay.RecoveryLine,
            overlay.IsAlert,
            overlay.IsTerminal);

        var linearProps = new LinearGradientBrushProperties
        {
            StartPoint = new Vector2(0, 0),
            EndPoint = new Vector2(0, height)
        };
        var linearStops = new[]
        {
            new GradientStop(0.0f, ColorUtil.ParseHex("#080a0e")),
            new GradientStop(1.0f, ColorUtil.ParseHex(tokens.Canvas))
        };
        using (var linearStopCollection = renderTarget.CreateGradientStopCollection(linearStops))
        using (var linearBrush = renderTarget.CreateLinearGradientBrush(linearProps, linearStopCollection))
        {
            renderTarget.FillRectangle(new Rect(0, 0, width, height), linearBrush);
        }

        var accentAlpha = paint.IsAlert ? 0.06f : 0.12f;
        var radialProps = new RadialGradientBrushProperties
        {
            Center = new Vector2(width * 0.5f, height * 0.38f),
            GradientOriginOffset = Vector2.Zero,
            RadiusX = width * 0.8f,
            RadiusY = height * 0.5f
        };
        var radialStops = new[]
        {
            new GradientStop(0.0f, ColorUtil.ParseHex(tokens.Accent, accentAlpha)),
            new GradientStop(0.75f, ColorUtil.ParseHex("#000000", 0.0f))
        };
        using (var radialStopCollection = renderTarget.CreateGradientStopCollection(radialStops))
        using (var radialBrush = renderTarget.CreateRadialGradientBrush(radialProps, radialStopCollection))
        {
            renderTarget.FillRectangle(new Rect(0, 0, width, height), radialBrush);
        }

        var indeterminate = string.Equals(paint.ProgressMode, "indeterminate", StringComparison.OrdinalIgnoreCase);
        var allowPulse = indeterminate && !paint.IsAlert && !paint.IsTerminal;

        if (heroAsset is not null)
        {
            var heroSize = heroAsset.Bitmap.Size;
            var src = heroAsset.ContentSrc;
            if (src.Width <= 0 || src.Height <= 0)
            {
                src = new Rect(0, 0, heroSize.Width, heroSize.Height);
            }

            var pulse = allowPulse ? 1.0f + 0.015f * (float)Math.Sin(elapsedS * 1.4f) : 1.0f;
            var logoSize = Clamp(height * 0.11f, 88f, 168f) * pulse;
            var scale = Math.Min(logoSize / src.Width, logoSize / src.Height);
            var logoW = src.Width * scale;
            var logoH = src.Height * scale;
            var logoX = (width - logoW) * 0.5f;
            var logoY = (height - logoH) * 0.34f;
            renderTarget.DrawBitmap(
                heroAsset.Bitmap,
                new Rect(logoX, logoY, logoW, logoH),
                1f,
                Vortice.Direct2D1.BitmapInterpolationMode.Linear,
                src);
        }

        var dockX = (width - metrics.DockWidth) * 0.5f;
        var stackY = height * 0.52f;
        var taskText = string.IsNullOrWhiteSpace(paint.TaskLabel) ? "Getting things ready" : paint.TaskLabel;
        var taskRect = new Rect(dockX, stackY, metrics.DockWidth, metrics.TaskLineHeight * 2.4f);
        using (var taskBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Ink)))
        {
            renderTarget.DrawText(taskText, taskFormat, taskRect, taskBrush);
        }

        var cursorY = stackY + metrics.TaskLineHeight + metrics.TaskToDetailGap;
        if (!string.IsNullOrWhiteSpace(paint.DetailLabel))
        {
            var detailRect = new Rect(dockX, cursorY, metrics.DockWidth, metrics.DetailLineHeight * 2.2f);
            using var detailBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Muted));
            renderTarget.DrawText(paint.DetailLabel, detailFormat, detailRect, detailBrush);
            cursorY += metrics.DetailLineHeight + metrics.DetailToItemGap;
        }

        if (paint.ItemTotal > 0 && !paint.IsAlert && !paint.IsTerminal)
        {
            var itemText = $"{Math.Max(1, paint.ItemIndex)} of {paint.ItemTotal}";
            var itemRect = new Rect(dockX, cursorY, metrics.DockWidth, metrics.ItemLineHeight * 1.6f);
            using var itemBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.Dim));
            renderTarget.DrawText(itemText, itemFormat, itemRect, itemBrush);
            cursorY += metrics.ItemLineHeight + metrics.ItemToBarGap;
        }
        else
        {
            cursorY += metrics.ItemToBarGap;
        }

        if (!paint.IsAlert)
        {
            var barW = Clamp(width * 0.28f, 260f, 360f);
            var barH = tokens.Layout.ProgressHeight > 0 ? tokens.Layout.ProgressHeight : 3f;
            var barX = (width - barW) * 0.5f;
            var barY = Math.Max(cursorY, height * 0.62f);
            var fillColor = string.IsNullOrWhiteSpace(tokens.ProgressFill) ? tokens.Accent : tokens.ProgressFill;

            using (var trackBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(tokens.ProgressTrack)))
            {
                var trackRect = new RoundedRectangle { Rect = new Rect(barX, barY, barW, barH), RadiusX = 1.5f, RadiusY = 1.5f };
                renderTarget.FillRoundedRectangle(trackRect, trackBrush);
            }

            using var fillBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(fillColor));
            if (!indeterminate)
            {
                var pct = (float)ProgressFillAnimator.Resolve(paint.ProgressPct, paint.ProgressMode);
                var fillW = barW * (pct / 100f);
                if (fillW > 0.1f)
                {
                    var fillRect = new RoundedRectangle { Rect = new Rect(barX, barY, fillW, barH), RadiusX = 1.5f, RadiusY = 1.5f };
                    renderTarget.FillRoundedRectangle(fillRect, fillBrush);
                }
            }
            else
            {
                var cycle = (elapsedS * 0.55f) % 1.0f;
                var segW = barW * 0.28f;
                var segX = barX + (barW - segW) * cycle;
                var fillRect = new RoundedRectangle { Rect = new Rect(segX, barY, segW, barH), RadiusX = 1.5f, RadiusY = 1.5f };
                renderTarget.FillRoundedRectangle(fillRect, fillBrush);
            }
        }

        if (!string.IsNullOrWhiteSpace(paint.RecoveryLine))
        {
            var bannerColor = paint.BannerKind switch
            {
                "fail" => tokens.Fail,
                "warn" => tokens.Warn,
                _ => tokens.Muted
            };
            var bannerMaxWidth = Math.Min(480f, width * 0.88f);
            var bannerRect = new Rect(
                (width - bannerMaxWidth) * 0.5f,
                height - Clamp(height * 0.12f, 64f, 96f),
                bannerMaxWidth,
                56f);
            using var bannerBrush = renderTarget.CreateSolidColorBrush(ColorUtil.ParseHex(bannerColor));
            renderTarget.DrawText(paint.RecoveryLine, bannerFormat, bannerRect, bannerBrush);
        }
    }

    private readonly record struct PaintModel(
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
}
