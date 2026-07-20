using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.WIC;

namespace WinMintSetupShell;

internal static class RenderSelfTest
{
    private const int Width = 1280;
    private const int Height = 800;

    public static void Run(string shellRoot, string outputPath, DesignTokens tokens, ShellLogger? logger = null)
    {
        var status = new SetupShellStatus
        {
            Phase = "running",
            StageId = "apps",
            TaskLabel = "Installing your apps",
            DetailLabel = "Installing Cursor",
            ItemIndex = 2,
            ItemTotal = 5,
            ProgressPct = 42,
            ProgressMode = "determinate",
            ProfileName = "WinMint",
            ElapsedMs = 125_000
        };

        using var d2dFactory = D2D1.D2D1CreateFactory<ID2D1Factory>();
        using var dwFactory = DWrite.DWriteCreateFactory<IDWriteFactory>();
        using var wicFactory = new IWICImagingFactory();
        using var wicBitmap = wicFactory.CreateBitmap(
            Width,
            Height,
            Vortice.WIC.PixelFormat.Format32bppPBGRA,
            BitmapCreateCacheOption.CacheOnLoad);

        var rtProps = new RenderTargetProperties(
            RenderTargetType.Default,
            new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            96f,
            96f,
            RenderTargetUsage.None,
            FeatureLevel.Default);

        var renderTarget = d2dFactory.CreateWicBitmapRenderTarget(wicBitmap, rtProps);
        var fontCollection = dwFactory.GetSystemFontCollection(false);
        try
        {
            var metrics = SplashLayout.Resolve(Width, Height, tokens.Layout);
            using var taskFormat = dwFactory.CreateTextFormat(
                tokens.FontFamily,
                fontCollection,
                FontWeight.Medium,
                FontStyle.Normal,
                FontStretch.Normal,
                metrics.TaskFontSize);
            taskFormat.TextAlignment = TextAlignment.Center;
            taskFormat.ParagraphAlignment = ParagraphAlignment.Near;
            taskFormat.WordWrapping = WordWrapping.Wrap;

            using var detailFormat = dwFactory.CreateTextFormat(
                tokens.FontFamily,
                fontCollection,
                FontWeight.Normal,
                FontStyle.Normal,
                FontStretch.Normal,
                metrics.DetailFontSize);
            detailFormat.TextAlignment = TextAlignment.Center;
            detailFormat.ParagraphAlignment = ParagraphAlignment.Near;
            detailFormat.WordWrapping = WordWrapping.Wrap;

            using var itemFormat = dwFactory.CreateTextFormat(
                tokens.FontFamily,
                fontCollection,
                FontWeight.Normal,
                FontStyle.Normal,
                FontStretch.Normal,
                metrics.ItemFontSize);
            itemFormat.TextAlignment = TextAlignment.Center;
            itemFormat.ParagraphAlignment = ParagraphAlignment.Near;

            using var bannerFormat = dwFactory.CreateTextFormat(
                tokens.FontFamily,
                fontCollection,
                FontWeight.Normal,
                FontStyle.Normal,
                FontStretch.Normal,
                13f);
            bannerFormat.TextAlignment = TextAlignment.Center;
            bannerFormat.ParagraphAlignment = ParagraphAlignment.Center;

            using var heroAsset = SplashPainter.LoadHeroBitmap(renderTarget, shellRoot, logger);
            if (heroAsset is null)
            {
                throw new InvalidOperationException($"Hero bitmap could not be loaded from {shellRoot}.");
            }

            SystemAccessibility.Refresh();
            renderTarget.BeginDraw();
            SplashPainter.Paint(
                renderTarget,
                Width,
                Height,
                SystemAccessibility.ResolvePaintTokens(tokens),
                status,
                heroAsset,
                taskFormat,
                detailFormat,
                itemFormat,
                bannerFormat,
                stalled: false,
                reduceMotion: SystemAccessibility.ReduceMotion);
            renderTarget.EndDraw();
        }
        finally
        {
            renderTarget.Dispose();
        }

        var announcement = SystemAccessibility.BuildAnnouncement(status, stalled: false);
        if (!announcement.Contains("Installing your apps", StringComparison.Ordinal)
            || !announcement.Contains("Installing Cursor", StringComparison.Ordinal)
            || !announcement.Contains("2 of 5", StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"Accessibility announcement missing expected status text: {announcement}");
        }

        if (!string.IsNullOrWhiteSpace(outputPath))
        {
            SplashPainter.SaveWicBitmapPng(wicBitmap, outputPath);
        }
    }
}
