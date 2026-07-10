namespace WinMintSetupShell;

public sealed class AppOptions
{
    public string ShellRoot { get; set; } = "";
    public string StatusPath { get; set; } = "";
    public string ControlPath { get; set; } = "";
    public string RuntimeStatePath { get; set; } = "";
    public int PollMs { get; set; } = 1500;
    public int MinStartDwellMs { get; set; } = 5000;
    public int MinCompleteDwellMs { get; set; } = 5000;
    public bool EnableLog { get; set; }
    public bool RenderTest { get; set; }
    public bool Preview { get; set; }
    public bool Wizard { get; set; }
    public string RepoRoot { get; set; } = "";
    public string GuestCapturePath { get; set; } = @"C:\Windows\Temp\winmint-setup-shell-guest.png";

    public static AppOptions Parse(string[] args)
    {
        var options = new AppOptions();
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--shell-root" when i + 1 < args.Length:
                    options.ShellRoot = args[++i].Trim('"');
                    break;
                case "--status" when i + 1 < args.Length:
                    options.StatusPath = args[++i].Trim('"');
                    break;
                case "--control" when i + 1 < args.Length:
                    options.ControlPath = args[++i].Trim('"');
                    break;
                case "--runtime-state" when i + 1 < args.Length:
                    options.RuntimeStatePath = args[++i].Trim('"');
                    break;
                case "--poll-ms" when i + 1 < args.Length:
                    options.PollMs = Math.Max(500, int.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture));
                    break;
                case "--min-start-dwell-ms" when i + 1 < args.Length:
                    options.MinStartDwellMs = Math.Max(0, int.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture));
                    break;
                case "--min-complete-dwell-ms" when i + 1 < args.Length:
                    options.MinCompleteDwellMs = Math.Max(0, int.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture));
                    break;
                case "--log":
                    options.EnableLog = true;
                    break;
                case "--guest-capture" when i + 1 < args.Length:
                    options.GuestCapturePath = args[++i].Trim('"');
                    break;
                case "--render-test":
                    options.RenderTest = true;
                    break;
                case "--preview":
                    options.Preview = true;
                    break;
                case "--wizard":
                    options.Wizard = true;
                    break;
                case "--repo-root" when i + 1 < args.Length:
                    options.RepoRoot = args[++i].Trim('"');
                    break;
            }
        }

        if (string.IsNullOrWhiteSpace(options.ShellRoot))
        {
            throw new ArgumentException("--shell-root is required.");
        }

        if (options.Wizard && string.IsNullOrWhiteSpace(options.RepoRoot))
        {
            throw new ArgumentException("--repo-root is required with --wizard.");
        }

        var winMintDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WinMint");
        if (string.IsNullOrWhiteSpace(options.StatusPath))
        {
            options.StatusPath = Path.Combine(winMintDir, "setup-shell-status.json");
        }
        if (string.IsNullOrWhiteSpace(options.ControlPath))
        {
            options.ControlPath = Path.Combine(winMintDir, "setup-shell-control.json");
        }
        if (string.IsNullOrWhiteSpace(options.RuntimeStatePath))
        {
            options.RuntimeStatePath = Path.Combine(winMintDir, "runtime-state.json");
        }

        return options;
    }
}
