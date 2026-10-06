using System.IO.Compression;
using System.Text.Json;

using WinMint.Contracts;

namespace WinMint.Provisioning;

internal sealed record ShellDesktopRequest(
    IReadOnlyList<string> WingetIds,
    IProcessHost Processes,
    IAssetDownload? AssetDownload,
    string GuestDesktopRoot,
    string ThideInstallDir,
    string YasbConfigDir,
    string KomorebiConfigDir,
    string WhkdrcPath,
    string? ArchitectureOverride = null);

internal sealed record ShellDesktopApplyResult(
    string? TaskbarSurface,
    bool Komorebi,
    bool YasbOk,
    bool ThideOk,
    bool KomorebiOk,
    bool RecoveredTaskbar,
    IReadOnlyList<string> Notes);

internal static class ShellDesktop
{
    public static async Task<ShellDesktopApplyResult> ApplyAsync(
        ShellDesktopRequest request,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        List<string> notes = [];
        bool yasb = ContainsId(request.WingetIds, PackageIds.Yasb);
        bool komorebi = ContainsId(request.WingetIds, PackageIds.Komorebi);
        if (!yasb && !komorebi)
        {
            return new ShellDesktopApplyResult(null, false, true, true, true, false, notes);
        }

        bool yasbOk = true;
        bool thideOk = true;
        bool komorebiOk = true;
        bool recovered = false;
        string? thideExe = null;
        bool hideAttempted = false;

        if (yasb)
        {
            try
            {
                string variant = ShellDesktopLayout.SelectYasbVariant(komorebi);
                string sourceDir = Path.Combine(request.GuestDesktopRoot, "yasb", variant);
                Directory.CreateDirectory(request.YasbConfigDir);
                CopyYasbAsset(sourceDir, "config.yaml", Path.Combine(request.YasbConfigDir, "config.yaml"));
                CopyYasbAsset(sourceDir, "styles.css", Path.Combine(request.YasbConfigDir, "styles.css"));

                yasbOk = await TryStartYasbAsync(request.Processes, ct).ConfigureAwait(false);
                if (!yasbOk)
                {
                    notes.Add("yasb start failed");
                }

                (thideOk, thideExe, hideAttempted) = await TryEnableThideAsync(request, ct).ConfigureAwait(false);
                if (!thideOk)
                {
                    notes.Add("thide enable failed");
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                yasbOk = false;
                notes.Add($"yasb path failed: {ex.Message}");
            }

            if (hideAttempted && (!yasbOk || !thideOk) && thideExe is not null)
            {
                recovered = await TryRecoverThideAsync(request.Processes, thideExe, ct).ConfigureAwait(false);
                if (recovered)
                {
                    notes.Add("thide recovery attempted");
                }
            }
        }

        if (komorebi)
        {
            try
            {
                komorebiOk = await TryConfigureKomorebiAsync(request, ct).ConfigureAwait(false);
                if (!komorebiOk)
                {
                    notes.Add("komorebi configure failed");
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                komorebiOk = false;
                notes.Add($"komorebi path failed: {ex.Message}");
            }
        }

        string? surface = yasb ? "yasb" : null;
        ShellDesktopApplyResult result = new(
            surface,
            komorebi,
            yasbOk,
            thideOk,
            komorebiOk,
            recovered,
            notes);
        WriteEvidence(result);
        return result;
    }

    private static bool ContainsId(IReadOnlyList<string> ids, string wingetId)
    {
        foreach (string id in ids)
        {
            if (id.Equals(wingetId, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static void CopyYasbAsset(string sourceDir, string leaf, string destination)
    {
        string source = Path.Combine(sourceDir, leaf);
        if (!File.Exists(source))
        {
            throw new FileNotFoundException($"Missing staged YASB asset '{leaf}'.", source);
        }

        if (leaf.Equals("config.yaml", StringComparison.OrdinalIgnoreCase) && File.Exists(destination))
        {
            string backup = destination + ".bak";
            if (!File.Exists(backup))
            {
                File.Copy(destination, backup, overwrite: false);
            }
        }

        File.Copy(source, destination, overwrite: true);
    }

    private static async Task<bool> TryStartYasbAsync(IProcessHost processes, CancellationToken ct)
    {
        string? yasbc = TryResolveOnPath("yasbc.exe") ?? TryResolveOnPath("yasbc");
        if (yasbc is not null)
        {
            ProcessStartResult started = await processes.RunAsync(yasbc, ["start"], ct).ConfigureAwait(false);
            return started.ExitCode == 0;
        }

        string? yasb = TryResolveOnPath("yasb.exe") ?? TryResolveOnPath("yasb");
        if (yasb is null)
        {
            return false;
        }

        ProcessStartResult fallback = await processes.RunAsync(yasb, [], ct).ConfigureAwait(false);
        return fallback.ExitCode == 0;
    }

    private static async Task<(bool Ok, string? ThideExe, bool HideAttempted)> TryEnableThideAsync(
        ShellDesktopRequest request,
        CancellationToken ct)
    {
        if (request.AssetDownload is null)
        {
            return (false, null, false);
        }

        ShellDesktopPins.ThidePin pin = ShellDesktopPins.ResolveThidePin(request.ArchitectureOverride);
        string? zipPath = await request.AssetDownload.TryDownloadVerifiedAsync(
            pin.Url,
            pin.Sha256Hex,
            Path.Combine(Path.GetTempPath(), "WinMint", "thide"),
            pin.ZipFileName,
            ct).ConfigureAwait(false);
        if (zipPath is null)
        {
            return (false, null, false);
        }

        Directory.CreateDirectory(request.ThideInstallDir);
        string? extracted = ExtractThideExe(zipPath, request.ThideInstallDir);
        if (extracted is null)
        {
            return (false, null, false);
        }

        ProcessStartResult autostart = await request.Processes.RunAsync(
            extracted,
            ["enable-autostart"],
            ct).ConfigureAwait(false);
        if (autostart.ExitCode != 0)
        {
            return (false, extracted, false);
        }

        ProcessStartResult hide = await request.Processes.RunAsync(extracted, ["hide"], ct).ConfigureAwait(false);
        return (hide.ExitCode == 0, extracted, true);
    }

    private static async Task<bool> TryRecoverThideAsync(
        IProcessHost processes,
        string thideExe,
        CancellationToken ct)
    {
        _ = await processes.RunAsync(thideExe, ["show"], ct).ConfigureAwait(false);
        _ = await processes.RunAsync(thideExe, ["stop"], ct).ConfigureAwait(false);
        ProcessStartResult disable = await processes.RunAsync(thideExe, ["disable-autostart"], ct)
            .ConfigureAwait(false);
        return disable.ExitCode == 0;
    }

    private static async Task<bool> TryConfigureKomorebiAsync(ShellDesktopRequest request, CancellationToken ct)
    {
        string templatePath = Path.Combine(request.GuestDesktopRoot, "komorebi", "komorebi.json.template");
        string whkdSource = Path.Combine(request.GuestDesktopRoot, "komorebi", "whkdrc");
        if (!File.Exists(templatePath) || !File.Exists(whkdSource))
        {
            return false;
        }

        Directory.CreateDirectory(request.KomorebiConfigDir);
        string? whkdParent = Path.GetDirectoryName(request.WhkdrcPath);
        if (!string.IsNullOrWhiteSpace(whkdParent))
        {
            Directory.CreateDirectory(whkdParent);
        }

        File.Copy(whkdSource, request.WhkdrcPath, overwrite: true);

        int monitorCount = ShellDesktopLayout.TryGetConnectedMonitorCount();
        string monitorsJson = ShellDesktopLayout.BuildKomorebiMonitorsJson(monitorCount);
        string displayPrefsJson = ShellDesktopLayout.BuildDisplayIndexPreferencesJson([]);
        string rendered = ShellDesktopLayout.RenderKomorebiConfig(
            await File.ReadAllTextAsync(templatePath, ct).ConfigureAwait(false),
            monitorsJson,
            displayPrefsJson);
        await File.WriteAllTextAsync(
            Path.Combine(request.KomorebiConfigDir, "komorebi.json"),
            rendered,
            ct).ConfigureAwait(false);

        string? komorebic = TryResolveOnPath("komorebic.exe") ?? TryResolveOnPath("komorebic");
        if (komorebic is null)
        {
            return false;
        }

        ProcessStartResult enable = await request.Processes.RunAsync(
            komorebic,
            ["enable-autostart", "--whkd"],
            ct).ConfigureAwait(false);
        return enable.ExitCode == 0;
    }

    private static string? ExtractThideExe(string zipPath, string installDir)
    {
        using ZipArchive archive = ZipFile.OpenRead(zipPath);
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            if (!entry.Name.Equals("thide.exe", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            string destination = Path.Combine(installDir, "thide.exe");
            entry.ExtractToFile(destination, overwrite: true);
            return destination;
        }

        return null;
    }

    private static string? TryResolveOnPath(string fileName)
    {
        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathEnv))
        {
            return null;
        }

        foreach (string segment in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                string candidate = Path.Combine(segment.Trim(), fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
                // ponytail: skip malformed PATH segments
            }
        }

        return null;
    }

    private static void WriteEvidence(ShellDesktopApplyResult result)
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "evidence");
        Directory.CreateDirectory(dir);
        ShellDesktopEvidenceFile document = new(
            ShellDesktopEvidenceFile.SchemaVersionValue,
            result.TaskbarSurface,
            result.Komorebi,
            result.YasbOk,
            result.ThideOk,
            result.KomorebiOk,
            result.RecoveredTaskbar,
            result.Notes);
        File.WriteAllBytes(
            Path.Combine(dir, "shell.desktop.json"),
            JsonSerializer.SerializeToUtf8Bytes(document, ProvisioningJsonContext.Default.ShellDesktopEvidenceFile));
    }
}
