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
            GroupLabel = "Setting up",
            TaskLabel = "Preparing your system…",
            StepIndex = 2,
            StepTotal = 4,
            ProfileName = "WinMint",
            ElapsedMs = 125_000,
            Steps =
            [
                new SetupShellStep { Id = "prepare", Label = "Prepare", Status = "done" },
                new SetupShellStep { Id = "agent", Label = "Install apps", Status = "current" },
                new SetupShellStep { Id = "shell", Label = "Configure desktop", Status = "pending" },
                new SetupShellStep { Id = "finish", Label = "Finish", Status = "pending" }
            ]
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
            var metrics = SplashLayout.Resolve(Width, Height, tokens.Layout, status.Steps!.Count);
            using var groupFormat = dwFactory.CreateTextFormat(
                tokens.FontFamily,
                fontCollection,
                FontWeight.SemiBold,
                FontStyle.Normal,
                FontStretch.Normal,
                metrics.GroupFontSize);
            groupFormat.TextAlignment = TextAlignment.Center;
            groupFormat.ParagraphAlignment = ParagraphAlignment.Near;

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

            using var stepFormat = dwFactory.CreateTextFormat(
                tokens.FontFamily,
                fontCollection,
                FontWeight.Normal,
                FontStyle.Normal,
                FontStretch.Normal,
                metrics.StepFontSize);
            stepFormat.TextAlignment = TextAlignment.Center;
            stepFormat.ParagraphAlignment = ParagraphAlignment.Near;

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

            renderTarget.BeginDraw();
            SplashPainter.Paint(
                renderTarget,
                Width,
                Height,
                tokens,
                status,
                heroAsset,
                groupFormat,
                taskFormat,
                stepFormat,
                bannerFormat);
            renderTarget.EndDraw();
        }
        finally
        {
            renderTarget.Dispose();
        }

        if (!string.IsNullOrWhiteSpace(outputPath))
        {
            SplashPainter.SaveWicBitmapPng(wicBitmap, outputPath);
        }
    }
}
