namespace WinMintSetupShell;

internal readonly struct SplashLayoutMetrics
{
    public float DockLeft { get; init; }
    public float DockWidth { get; init; }
    public float TaskFontSize { get; init; }
    public float DetailFontSize { get; init; }
    public float ItemFontSize { get; init; }
    public float TaskLineHeight { get; init; }
    public float DetailLineHeight { get; init; }
    public float ItemLineHeight { get; init; }
    public float TaskToDetailGap { get; init; }
    public float DetailToItemGap { get; init; }
    public float ItemToBarGap { get; init; }
}

internal static class SplashLayout
{
    public static SplashLayoutMetrics Resolve(int width, int height, LayoutTokens tokens)
    {
        var shortHeight = height < 720;
        var dockWidth = Math.Min(tokens.DockMaxWidth, width * 0.92f);
        var dockLeft = (width - dockWidth) * 0.5f;
        var gapScale = shortHeight ? 0.9f : 1.1f;

        var taskFontSize = tokens.TaskFontSize > 0
            ? tokens.TaskFontSize
            : Clamp(width * 0.018f, 17f, 22f);
        var detailFontSize = tokens.DetailFontSize > 0
            ? tokens.DetailFontSize
            : Clamp(width * 0.014f, 14f, 16f);
        var itemFontSize = tokens.GroupFontSize > 0 ? tokens.GroupFontSize : 13f;

        return new SplashLayoutMetrics
        {
            DockLeft = dockLeft,
            DockWidth = dockWidth,
            TaskFontSize = taskFontSize,
            DetailFontSize = detailFontSize,
            ItemFontSize = itemFontSize,
            TaskLineHeight = taskFontSize * 1.35f,
            DetailLineHeight = detailFontSize * 1.4f,
            ItemLineHeight = itemFontSize * 1.35f,
            TaskToDetailGap = 10f * gapScale,
            DetailToItemGap = 8f * gapScale,
            ItemToBarGap = 22f * gapScale
        };
    }

    private static float Clamp(float value, float min, float max) => Math.Max(min, Math.Min(max, value));
}
