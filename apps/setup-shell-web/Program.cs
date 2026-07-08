namespace WinMintSetupShell;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        ShellLogger? logger = null;
        AppOptions? options = null;
        Application.ThreadException += (_, e) =>
        {
            logger?.Info($"setup shell fatal: {e.Exception.Message}");
            Environment.Exit(1);
        };
        try
        {
            options = AppOptions.Parse(args);
            var uiName = options.Wizard ? "wizard.html" : "index.html";
            if (!File.Exists(Path.Combine(options.ShellRoot, uiName)))
            {
                throw new FileNotFoundException(
                    $"UI asset '{uiName}' is missing under {options.ShellRoot}. Rebuild the ISO or run tools/release/Build-WinMintSetupShell.ps1.");
            }

            var logDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WinMint", "Logs");
            logger = new ShellLogger(logDir, options.EnableLog);
            logger.Info($"host=webview2 preview={options.Preview} wizard={options.Wizard} shellRoot={options.ShellRoot}");

            if (options.Wizard)
            {
                var repoRoot = WizardBridge.ResolveRepoRoot(options.RepoRoot, AppContext.BaseDirectory);
                Application.Run(new WizardWebForm(options, logger, repoRoot));
            }
            else
            {
                Application.Run(new SetupShellWebForm(options, logger));
            }

            return 0;
        }
        catch (Exception ex)
        {
            logger?.Info($"setup shell fatal: {ex.Message}");
            return 1;
        }
        finally
        {
            if (options is not null && !options.Wizard)
            {
                DesktopGuard.DismissStartMenu();
                DesktopGuard.ShowTaskbars();
                DesktopGuard.ClearNoWinKeys();
                DesktopGuard.ClearDisableTaskSwitching();
            }
        }
    }
}
