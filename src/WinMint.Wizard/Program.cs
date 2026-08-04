using Avalonia;

namespace WinMint.Wizard;

internal static class Program
{
    // Entry point — no Avalonia types / SynchronizationContext use before StartWithClassicDesktopLifetime
    // (avalonia-docs: application-lifetimes).
    [STAThread]
    public static int Main(string[] args) =>
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);

    // Needed for IDE previewer infrastructure.
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>().UsePlatformDetect();
}
