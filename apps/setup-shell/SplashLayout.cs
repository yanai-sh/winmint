namespace WinMintSetupShell;

internal readonly struct SplashLayoutMetrics
{
    public float DockLeft { get; init; }
    public float DockWidth { get; init; }
    public float DockTop { get; init; }
    public float BrandAreaTop { get; init; }
    public float BrandAreaBottom { get; init; }
    public float HeroMaxWidth { get; init; }
    public float HeroMaxHeight { get; init; }
    public float GroupFontSize { get; init; }
    public float TaskFontSize { get; init; }
    public float StepFontSize { get; init; }
    public float GroupLineHeight { get; init; }
    public float TaskLineHeight { get; init; }
    public float StepLineHeight { get; init; }
    public float GroupToTaskGap { get; init; }
    public float TaskToStepsGap { get; init; }
    public float StepsToMetaGap { get; init; }
    public float MetaLineHeight { get; init; }
    public int StepCount { get; init; }
    public float BannerOffsetBottom { get; init; }
    public float BannerMaxWidth { get; init; }
    public float SpinnerCenterY { get; init; }
    public float SpinnerRadius { get; init; }
    public bool ShowSpinner { get; init; }
}

internal static class SplashLayout
{
    public static SplashLayoutMetrics Resolve(int width, int height, LayoutTokens tokens, int stepCount = 0)
    {
        var shortHeight = height < 720;

        var padBottom = shortHeight
            ? Clamp(height * 0.08f, 32f, 56f)
            : Clamp(height * 0.10f, 48f, 88f);

        var dockWidth = Math.Min(tokens.DockMaxWidth, width * 0.92f);
        var dockLeft = (width - dockWidth) * 0.5f;

        var heroWidthCap = shortHeight
            ? Math.Min(520f, width * 0.88f)
            : Math.Min(tokens.HeroMaxWidth, width * 0.92f);
        var heroHeightCap = shortHeight
            ? Math.Min(120f, height * 0.22f)
            : Math.Min(tokens.HeroMaxHeight, height * 0.28f);

        var groupFontSize = tokens.GroupFontSize;
        var taskFontSize = Clamp(width * 0.0135f, tokens.TaskFontSize * 0.88f, tokens.TaskFontSize * 0.98f);
        var stepFontSize = shortHeight ? 10.5f : 11f;
        var gapScale = shortHeight ? 0.85f : 1f;
        var groupLineHeight = groupFontSize * 1.3f;
        var taskLineHeight = taskFontSize * 1.4f;
        var stepLineHeight = stepFontSize * 1.4f;
        var groupToTaskGap = 6f * gapScale;
        var taskToStepsGap = 8f * gapScale;
        var stepsToMetaGap = 10f * gapScale;
        var metaLineHeight = 14f;
        var taskBlockHeight = taskLineHeight * 2f;

        var stepLines = Math.Clamp(stepCount, 0, 8);
        var stepsBlockHeight = stepLines > 0 ? stepLines * stepLineHeight : 0f;
        var stepsGap = stepLines > 0 ? taskToStepsGap : 0f;
        var dockContentHeight = groupLineHeight + groupToTaskGap + taskBlockHeight + stepsGap + stepsBlockHeight + stepsToMetaGap + metaLineHeight;
        var dockTop = height - padBottom - dockContentHeight;
        dockTop = Math.Max(24f, dockTop);

        var brandAreaTop = Clamp(height * 0.06f, 24f, 48f);
        var brandGap = Clamp(height * 0.03f, 16f, 32f);
        var brandAreaBottom = Math.Max(brandAreaTop + 48f, dockTop - brandGap);

        var spinnerGap = Clamp(height * 0.035f, 20f, 28f);
        var showSpinner = false;
        var spinnerCenterY = dockTop - spinnerGap;
        var spinnerRadius = shortHeight ? 7f : 9f;

        var bannerOffsetBottom = Clamp(height * 0.08f, 48f, 72f);
        var bannerMaxWidth = Math.Min(420f, width * 0.90f);

        return new SplashLayoutMetrics
        {
            DockLeft = dockLeft,
            DockWidth = dockWidth,
            DockTop = dockTop,
            BrandAreaTop = brandAreaTop,
            BrandAreaBottom = brandAreaBottom,
            HeroMaxWidth = heroWidthCap,
            HeroMaxHeight = heroHeightCap,
            GroupFontSize = groupFontSize,
            TaskFontSize = taskFontSize,
            StepFontSize = stepFontSize,
            GroupLineHeight = groupLineHeight,
            TaskLineHeight = taskLineHeight,
            StepLineHeight = stepLineHeight,
            GroupToTaskGap = groupToTaskGap,
            TaskToStepsGap = taskToStepsGap,
            StepsToMetaGap = stepsToMetaGap,
            MetaLineHeight = metaLineHeight,
            StepCount = stepLines,
            BannerOffsetBottom = bannerOffsetBottom,
            BannerMaxWidth = bannerMaxWidth,
            SpinnerCenterY = spinnerCenterY,
            SpinnerRadius = spinnerRadius,
            ShowSpinner = showSpinner
        };
    }

    private static float Clamp(float value, float min, float max) => Math.Max(min, Math.Min(max, value));
}
