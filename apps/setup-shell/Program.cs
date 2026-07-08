using System.Runtime.InteropServices;
using System.Text.Json;

namespace WinMintSetupShell;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        SetupShellHost? host = null;
        ShellLogger? logger = null;
        try
        {
            var options = AppOptions.Parse(args);
            if (options.Wizard)
            {
                throw new InvalidOperationException(
                    "This WinMintSetupShell.Native build does not support --wizard. Use WinMintSetupShell.exe from tools/release/Build-WinMintSetupShell.ps1.");
            }

            var tokensPath = Path.Combine(options.ShellRoot, "tokens.json");
            if (!Directory.Exists(options.ShellRoot))
            {
                throw new DirectoryNotFoundException($"Setup shell assets are missing: {options.ShellRoot}");
            }

            var tokens = LoadTokens(tokensPath);
            if (options.RenderTest)
            {
                var renderLogDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "WinMint", "Logs");
                var renderLogger = options.EnableLog ? new ShellLogger(renderLogDir, true) : null;
                RenderSelfTest.Run(options.ShellRoot, options.GuestCapturePath, tokens, renderLogger);
                return 0;
            }

            var logDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WinMint", "Logs");
            logger = new ShellLogger(logDir, options.EnableLog);
            var arch = RuntimeInformation.ProcessArchitecture switch
            {
                Architecture.Arm64 => "arm64",
                Architecture.X64 => "x64",
                _ => "x86"
            };
            logger.Info($"host=native aot={arch} shellRoot={options.ShellRoot}");

            host = new SetupShellHost(options, logger, tokens);
            return host.Run();
        }
        catch (Exception ex)
        {
            logger?.Info($"setup shell fatal: {ex.Message}");
            return 1;
        }
        finally
        {
            host?.Dispose();
            DesktopGuard.DismissStartMenu();
            DesktopGuard.ShowTaskbars();
        }
    }

    private static DesignTokens LoadTokens(string path)
    {
        if (!File.Exists(path))
        {
            return new DesignTokens();
        }

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize(json, SetupShellJsonContext.Default.DesignTokens) ?? new DesignTokens();
        }
        catch
        {
            return new DesignTokens();
        }
    }
}
