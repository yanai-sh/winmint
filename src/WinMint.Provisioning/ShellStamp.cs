using System.Diagnostics;
using System.IO.Compression;

namespace WinMint.Provisioning;

/// <summary>
/// One-shot shell skel: Cascadia NF fonts, PowerShell profile/starship/WT settings, light chezmoi seed.
/// Write-if-missing only; never re-applies after the first successful stamp.
/// </summary>
internal static class ShellStamp
{
    public const string GuestSkelDirectory = @"C:\Windows\WinMint\shell-skel";
    public const string CascadiaVersion = "2407.24";

    private static readonly string[] WantedFonts = ["CascadiaCodeNF.ttf", "CascadiaMonoNF.ttf"];

    public static async Task<(bool Ok, string Message)> ApplyAsync(
        HttpMessageHandler? httpHandler,
        CancellationToken ct)
    {
        string skel = GuestSkelDirectory;
        if (!Directory.Exists(skel))
        {
            return (false, $"shell-skel missing at {skel}");
        }

        string markerDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "evidence");
        string markerPath = Path.Combine(markerDir, "shell.stamp.done");
        if (File.Exists(markerPath))
        {
            return (true, "shell.stamp already completed (marker present)");
        }

        List<string> notes = [];
        await InstallCascadiaFontsAsync(httpHandler, notes, ct).ConfigureAwait(false);
        StampPowerShellSkel(skel, notes);
        StampWindowsTerminalSettings(skel, notes);
        await SeedChezmoiAsync(skel, notes, ct).ConfigureAwait(false);

        Directory.CreateDirectory(markerDir);
        File.WriteAllText(markerPath, string.Join('\n', notes));
        return (true, string.Join("; ", notes));
    }

    /// <summary>Test seam: copy skel files with write-if-missing semantics.</summary>
    internal static void StampPowerShellSkelForTests(string skel, string documentsPowerShellDir, List<string> notes) =>
        StampPowerShellSkelTo(skel, documentsPowerShellDir, notes);

    private static void StampPowerShellSkel(string skel, List<string> notes)
    {
        string docs = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        StampPowerShellSkelTo(skel, Path.Combine(docs, "PowerShell"), notes);
    }

    private static void StampPowerShellSkelTo(string skel, string psDir, List<string> notes)
    {
        Directory.CreateDirectory(psDir);
        CopyIfMissing(
            Path.Combine(skel, "Microsoft.PowerShell_profile.ps1"),
            Path.Combine(psDir, "Microsoft.PowerShell_profile.ps1"),
            notes);
        CopyIfMissing(
            Path.Combine(skel, "powershell.config.json"),
            Path.Combine(psDir, "powershell.config.json"),
            notes);
        CopyIfMissing(
            Path.Combine(skel, "starship.toml"),
            Path.Combine(psDir, "starship.toml"),
            notes);
    }

    private static void StampWindowsTerminalSettings(string skel, List<string> notes)
    {
        string? target = ResolveWindowsTerminalSettingsPath();
        if (target is null)
        {
            notes.Add("wt.settings skipped (path not found)");
            return;
        }

        string source = Path.Combine(skel, "settings.json");
        if (!File.Exists(source))
        {
            notes.Add("wt.settings source missing");
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        if (File.Exists(target))
        {
            notes.Add("wt.settings kept (already present)");
            return;
        }

        File.Copy(source, target, overwrite: false);
        notes.Add("wt.settings stamped");
    }

    private static string? ResolveWindowsTerminalSettingsPath()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string unpackaged = Path.Combine(local, "Microsoft", "Windows Terminal", "settings.json");
        string packages = Path.Combine(local, "Packages");
        if (Directory.Exists(packages))
        {
            foreach (string dir in Directory.EnumerateDirectories(packages, "Microsoft.WindowsTerminal*"))
            {
                return Path.Combine(dir, "LocalState", "settings.json");
            }
        }

        return unpackaged;
    }

    private static void CopyIfMissing(string source, string dest, List<string> notes)
    {
        string name = Path.GetFileName(dest);
        if (!File.Exists(source))
        {
            notes.Add($"{name} source missing");
            return;
        }

        if (File.Exists(dest))
        {
            notes.Add($"{name} kept");
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
        File.Copy(source, dest, overwrite: false);
        notes.Add($"{name} stamped");
    }

    private static async Task InstallCascadiaFontsAsync(
        HttpMessageHandler? httpHandler,
        List<string> notes,
        CancellationToken ct)
    {
        string fontsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft",
            "Windows",
            "Fonts");
        Directory.CreateDirectory(fontsDir);

        if (WantedFonts.All(f => File.Exists(Path.Combine(fontsDir, f))))
        {
            notes.Add("cascadia fonts present");
            return;
        }

        string zipUrl =
            $"https://github.com/microsoft/cascadia-code/releases/download/v{CascadiaVersion}/CascadiaCode-{CascadiaVersion}.zip";
        string work = Path.Combine(Path.GetTempPath(), $"winmint-cascadia-{CascadiaVersion}");
        Directory.CreateDirectory(work);
        string zipPath = Path.Combine(work, "CascadiaCode.zip");

        try
        {
            using HttpClient client = httpHandler is null
                ? new HttpClient()
                : new HttpClient(httpHandler, disposeHandler: false);
            client.Timeout = TimeSpan.FromMinutes(5);
            await using Stream remote = await client.GetStreamAsync(zipUrl, ct).ConfigureAwait(false);
            await using FileStream file = File.Create(zipPath);
            await remote.CopyToAsync(file, ct).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            notes.Add($"cascadia download failed: {ex.Message}");
            return;
        }

        try
        {
            ZipFile.ExtractToDirectory(zipPath, work, overwriteFiles: true);
        }
        catch (Exception ex)
        {
            notes.Add($"cascadia extract failed: {ex.Message}");
            return;
        }

        string? ttfRoot = Directory.EnumerateFiles(work, "CascadiaCodeNF.ttf", SearchOption.AllDirectories)
            .Select(Path.GetDirectoryName)
            .FirstOrDefault();
        if (ttfRoot is null)
        {
            notes.Add("cascadia ttf not in zip");
            return;
        }

        foreach (string font in WantedFonts)
        {
            string src = Path.Combine(ttfRoot, font);
            string dest = Path.Combine(fontsDir, font);
            if (!File.Exists(src))
            {
                continue;
            }

            File.Copy(src, dest, overwrite: true);
            try
            {
                Microsoft.Win32.Registry.SetValue(
                    @"HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
                    $"{Path.GetFileNameWithoutExtension(font)} (TrueType)",
                    dest,
                    Microsoft.Win32.RegistryValueKind.String);
            }
            catch
            {
                // best-effort font registration
            }
        }

        notes.Add("cascadia fonts installed");
    }

    private static async Task SeedChezmoiAsync(string skel, List<string> notes, CancellationToken ct)
    {
        string? chezmoi = ResolveChezmoi();
        if (chezmoi is null)
        {
            notes.Add("chezmoi skipped (not on PATH)");
            return;
        }

        string sourceDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".local",
            "share",
            "chezmoi");
        string seedMarker = Path.Combine(sourceDir, ".winmint-seeded");
        if (File.Exists(seedMarker))
        {
            notes.Add("chezmoi already seeded");
            return;
        }

        string docsPs = Path.Combine(sourceDir, "Documents", "PowerShell");
        Directory.CreateDirectory(docsPs);
        foreach (string name in new[]
                 {
                     "Microsoft.PowerShell_profile.ps1",
                     "powershell.config.json",
                     "starship.toml",
                 })
        {
            string src = Path.Combine(skel, name);
            if (File.Exists(src))
            {
                File.Copy(src, Path.Combine(docsPs, name), overwrite: true);
            }
        }

        File.WriteAllText(seedMarker, "winmint");
        try
        {
            using Process process = new()
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = chezmoi,
                    ArgumentList = { "apply", "--force" },
                    UseShellExecute = false,
                    CreateNoWindow = true,
                },
            };
            process.Start();
            await process.WaitForExitAsync(ct).ConfigureAwait(false);
            notes.Add(process.ExitCode == 0 ? "chezmoi apply ok" : $"chezmoi apply exit {process.ExitCode}");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            notes.Add($"chezmoi apply failed: {ex.Message}");
        }
    }

    private static string? ResolveChezmoi()
    {
        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(pathEnv))
        {
            foreach (string dir in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            {
                string exe = Path.Combine(dir, "chezmoi.exe");
                if (File.Exists(exe))
                {
                    return exe;
                }
            }
        }

        string scoop = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims",
            "chezmoi.exe");
        return File.Exists(scoop) ? scoop : null;
    }
}
