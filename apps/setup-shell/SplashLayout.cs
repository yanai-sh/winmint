namespace WinMintSetupShell;

internal readonly struct SplashLayoutMetrics
{
    public float DockLeft { get; init; }
    public float DockWidth { get; init; }
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
    public float BannerOffsetBottom { get; init; }
    public float BannerMaxWidth { get; init; }
}

internal static class SplashLayout
{
    public static SplashLayoutMetrics Resolve(int width, int height, LayoutTokens tokens, int stepCount = 0)
    {
        var shortHeight = height < 720;

        var dockWidth = Math.Min(tokens.DockMaxWidth, width * 0.92f);
        var dockLeft = (width - dockWidth) * 0.5f;

        var groupFontSize = tokens.GroupFontSize > 0 ? tokens.GroupFontSize + 1f : 12f;
        var taskFontSize = Clamp(width * 0.016f, 16f, 20f);
        var stepFontSize = shortHeight ? 11f : 12f;
        var gapScale = shortHeight ? 0.9f : 1.1f;
        var groupLineHeight = groupFontSize * 1.3f;
        var taskLineHeight = taskFontSize * 1.4f;
        var stepLineHeight = stepFontSize * 1.4f;
        var groupToTaskGap = 6f * gapScale;
        var taskToStepsGap = 8f * gapScale;
        var stepsToMetaGap = 10f * gapScale;
        var metaLineHeight = 14f;

        var bannerOffsetBottom = Clamp(height * 0.08f, 48f, 72f);
        var bannerMaxWidth = Math.Min(420f, width * 0.90f);

        return new SplashLayoutMetrics
        {
            DockLeft = dockLeft,
            DockWidth = dockWidth,
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
            BannerOffsetBottom = bannerOffsetBottom,
            BannerMaxWidth = bannerMaxWidth
        };
    }

    private static float Clamp(float value, float min, float max) => Math.Max(min, Math.Min(max, value));
}
