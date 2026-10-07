using System.Text.Json;

using WinMint.Contracts;

namespace WinMint.Provisioning;

internal static partial class ProvisioningJobRunner
{
    private static async Task<JobsRunResult?> RunOneDriveUninstallJobAsync(
        JobRunnerEnv env,
        ProvisionJob job,
        CancellationToken ct)
    {
        string systemRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string[] candidates =
        [
            Path.Combine(systemRoot, "System32", "OneDriveSetup.exe"),
                Path.Combine(systemRoot, "SysWOW64", "OneDriveSetup.exe"),
            ];
        string? setup = candidates.FirstOrDefault(File.Exists);
        if (setup is null)
        {
            // Offline EraseOfflineOneDrive already removed Setup — FirstLogon is a safety net.
            return null;
        }

        try
        {
            ProcessStartResult started = await env.Guest.Processes.RunAsync(setup, ["/uninstall"], ct)
                .ConfigureAwait(false);
            // Non-zero is common when OneDrive was never fully installed; treat as best-effort ok.
            _ = started;
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: {ex.Message}");
        }
    }

    private static async Task<JobsRunResult?> RunShellDesktopJobAsync(
        JobRunnerEnv env,
        ProvisionJob job,
        IReadOnlyList<ProvisionJob> jobs,
        CancellationToken ct)
    {
        try
        {
            IReadOnlyList<string> ids = CollectAllWingetIds(jobs);
            await ShellSurfaces.ApplyDesktopAsync(env.Guest, ids, ct).ConfigureAwait(false);
            env.ReportStatus(new SessionStatus("shell.desktop", "Desktop surface applied (fail-open)."));
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            env.ReportStatus(new SessionStatus("shell.desktop", $"{job.Id}: {ex.Message}"));
            return null;
        }
    }

    private static JobsRunResult? RunShellChromeJob(
        JobRunnerEnv env,
        ProvisionJob job,
        IReadOnlyList<ProvisionJob> jobs)
    {
        try
        {
            IReadOnlyList<string> ids = CollectSelectedWingetIds(jobs);
            if (!env.Guest.ApplyShellChrome(
                    new ShellChromeRequest(
                        FailOpen: false,
                        SelectedWingetIds: ids,
                        RequireSelectedPins: env.PackageStrict)))
            {
                return FailJob(env, "jobs.failed", $"{job.Id}: shell chrome apply failed.");
            }

            env.ReportStatus(new SessionStatus("shell.chrome", "Start, taskbar, and bloom wallpaper applied."));
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: {ex.Message}");
        }
    }

    internal static List<string> CollectSelectedWingetIds(
        IReadOnlyList<ProvisionJob> jobs,
        string? importPath = null) =>
        CollectWingetIdsFromImport(jobs, importPath, ShellChromeLayout.IsPinApp);

    internal static List<string> CollectAllWingetIds(
        IReadOnlyList<ProvisionJob> jobs,
        string? importPath = null) =>
        CollectWingetIdsFromImport(jobs, importPath, static _ => true);

    private static List<string> CollectWingetIdsFromImport(
        IReadOnlyList<ProvisionJob> jobs,
        string? importPath,
        Func<string, bool> includeId)
    {
        List<string> ids = [];
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        foreach (ProvisionJob job in jobs)
        {
            if (job.Kind is ProvisionJobKind.Winget && !string.IsNullOrWhiteSpace(job.PackageId))
            {
                AddSelectedId(ids, seen, job.PackageId);
            }
        }

        if (!jobs.Any(j => j.Kind is ProvisionJobKind.WingetImport))
        {
            return ids;
        }

        string path = importPath ?? BundleLoader.DefaultGuestWingetImportPath;
        if (!File.Exists(path))
        {
            return ids;
        }

        using JsonDocument doc = JsonDocument.Parse(File.ReadAllBytes(path));
        if (!doc.RootElement.TryGetProperty("Sources", out JsonElement sources))
        {
            return ids;
        }

        foreach (JsonElement source in sources.EnumerateArray())
        {
            if (!source.TryGetProperty("Packages", out JsonElement packages))
            {
                continue;
            }

            foreach (JsonElement package in packages.EnumerateArray())
            {
                if (!package.TryGetProperty("PackageIdentifier", out JsonElement idEl))
                {
                    continue;
                }

                string? id = idEl.GetString();
                if (id is not null && includeId(id))
                {
                    AddSelectedId(ids, seen, id);
                }
            }
        }

        return ids;
    }

    private static void AddSelectedId(List<string> ids, HashSet<string> seen, string id)
    {
        if (seen.Add(id))
        {
            ids.Add(id);
        }
    }

    private static JobsRunResult? RunWorkstationQuietJob(
        JobRunnerEnv env,
        ProvisionJob job)
    {
        try
        {
            env.Guest.ApplyWorkstationQuiet();
            SessionStatus ok = new("jobs.workstation.quiet", "Dark theme and quiet user defaults applied.");
            env.ReportStatus(ok);
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: {ex.Message}");
        }
    }

    private static Task<JobsRunResult?> RunReservedStorageDisableJobAsync(
        JobRunnerEnv env,
        ProvisionJob job,
        CancellationToken ct)
    {
        // ponytail: DISM /Online /Set-ReservedStorageState requires SYSTEM. Supervisor
        // --machine-setup runs it hidden. FirstLogon is medium-IL (exit 740) and must not fail S4.
        _ = env;
        _ = job;
        _ = ct;
        return Task.FromResult<JobsRunResult?>(null);
    }

    private static async Task<JobsRunResult?> RunDohSetJobAsync(
        JobRunnerEnv env,
        ProvisionJob job,
        CancellationToken ct)
    {
        // Plan-emitted params only — no guest DoH provider table (ProductPosture owns the catalog).
        if (string.IsNullOrWhiteSpace(job.DohPrimary)
            || string.IsNullOrWhiteSpace(job.DohSecondary)
            || string.IsNullOrWhiteSpace(job.DohTemplate))
        {
            return FailJob(
                env,
                "jobs.failed",
                $"Job '{job.Id}' kind doh.set requires dohPrimary/dohSecondary/dohTemplate from the plan.");
        }

        string primary = job.DohPrimary;
        string secondary = job.DohSecondary;
        string template = job.DohTemplate;

        // Inbox powershell.exe only — not guest pwsh product control plane (scoop bootstrap precedent).
        string command =
            $"$up = Get-NetAdapter | Where-Object Status -eq 'Up'; " +
            $"foreach ($a in $up) {{ Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @('{primary}','{secondary}') }}; " +
            $"foreach ($ip in @('{primary}','{secondary}')) {{ " +
            $"try {{ Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate '{template}' -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop }} catch {{ }}; " +
            $"try {{ Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate '{template}' -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop }} catch {{ }} }}";

        try
        {
            ProcessStartResult started = await env.Guest.Processes.RunAsync(
                    "powershell.exe",
                    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
                    ct)
                .ConfigureAwait(false);
            if (started.ExitCode != 0)
            {
                return FailJob(env, "jobs.failed", $"{job.Id}: DoH configure exited {started.ExitCode}.");
            }

            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"{job.Id}: {ex.Message}");
        }
    }

    private static async Task<JobsRunResult?> RunAppxSafetyNetJobAsync(
        JobRunnerEnv env,
        ProvisionJob job,
        CancellationToken ct)
    {
        if (env.Guest.Appx is null)
        {
            return FailJob(env, "jobs.failed", $"Job '{job.Id}' requires IAppxPackageManager.");
        }

        IReadOnlyList<string> ids = env.RemoveProvisionedAppx;
        try
        {
            env.ReportStatus(new SessionStatus(
                $"jobs.{job.Id}.running",
                $"{job.Id} online AppX safety net…"));
            // Strip goal: gone is success. Already-absent catalog ids are silent (no phase, no fail).
            // FU marks are best-effort; offline DISM owns provisioned remove.
            HashSet<string> families = new(StringComparer.OrdinalIgnoreCase);
            foreach (string catalogId in ids)
            {
                if (string.IsNullOrWhiteSpace(catalogId))
                {
                    continue;
                }

                bool touched = false;
                foreach (AppxPackageInfo registered in env.Guest.Appx.FindRegisteredByCatalogId(catalogId))
                {
                    await env.Guest.Appx.RemovePackageAsync(registered.PackageFullName, ct).ConfigureAwait(false);
                    touched = true;
                    if (!string.IsNullOrWhiteSpace(registered.PackageFamilyName))
                    {
                        families.Add(registered.PackageFamilyName);
                    }
                }

                foreach (AppxPackageInfo provisioned in env.Guest.Appx.FindProvisionedByCatalogId(catalogId))
                {
                    await env.Guest.Appx.DeprovisionPackageFamilyAsync(provisioned.PackageFamilyName, ct)
                        .ConfigureAwait(false);
                    touched = true;
                    if (!string.IsNullOrWhiteSpace(provisioned.PackageFamilyName))
                    {
                        families.Add(provisioned.PackageFamilyName);
                    }
                }

                if (touched)
                {
                    env.ReportStatus(new SessionStatus(
                        $"removed.appx.online.{catalogId}",
                        $"Removed online AppX catalog id '{catalogId}'."));
                }

                string stampPfn = families.FirstOrDefault(pfn =>
                    pfn.StartsWith(catalogId + "_", StringComparison.OrdinalIgnoreCase))
                    ?? AppxCatalogFamilyNames.Resolve(catalogId);
                families.Add(stampPfn);
            }

            foreach (string pfn in families.OrderBy(s => s, StringComparer.OrdinalIgnoreCase))
            {
                if (!env.Guest.Appx.EnsureDeprovisionedMark(pfn))
                {
                    // ponytail: medium-IL may lack HKLM; absence already satisfies the strip
                    continue;
                }

                env.ReportStatus(new SessionStatus(
                    $"deprovisioned.appx.{pfn}",
                    $"Ensured deprovisioned mark for '{pfn}'."));
            }

            foreach (string catalogId in ids)
            {
                if (string.IsNullOrWhiteSpace(catalogId))
                {
                    continue;
                }

                if (env.Guest.Appx.FindRegisteredByCatalogId(catalogId).Count > 0
                    || env.Guest.Appx.FindProvisionedByCatalogId(catalogId).Count > 0)
                {
                    return FailJob(
                        env,
                        "jobs.failed",
                        $"Job '{job.Id}': '{catalogId}' still present after safety net.");
                }
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"Job '{job.Id}': {ex.Message}");
        }

        return null;
    }
}

