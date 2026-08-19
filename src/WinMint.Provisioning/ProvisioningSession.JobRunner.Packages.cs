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
            // Already gone — product-constant uninstall is idempotent.
            return null;
        }

        try
        {
            ProcessStartResult started = await env.Processes.RunAsync(setup, ["/uninstall", "/allusers"], ct)
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

    private static JobsRunResult? RunWorkstationQuietJob(
        JobRunnerEnv env,
        ProvisionJob job)
    {
        try
        {
            env.ApplyWorkstationQuiet();
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
            ProcessStartResult started = await env.Processes.RunAsync(
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
        if (env.Appx is null)
        {
            return FailJob(env, "jobs.failed", $"Job '{job.Id}' requires IAppxPackageManager.");
        }

        IReadOnlyList<string> ids = env.RemoveProvisionedAppx;
        try
        {
            HashSet<string> families = new(StringComparer.OrdinalIgnoreCase);
            foreach (string catalogId in ids)
            {
                if (string.IsNullOrWhiteSpace(catalogId))
                {
                    continue;
                }

                foreach (AppxPackageInfo registered in env.Appx.FindRegisteredByCatalogId(catalogId))
                {
                    await env.Appx.RemovePackageAsync(registered.PackageFullName, ct).ConfigureAwait(false);
                    if (!string.IsNullOrWhiteSpace(registered.PackageFamilyName))
                    {
                        families.Add(registered.PackageFamilyName);
                    }
                }

                foreach (AppxPackageInfo provisioned in env.Appx.FindProvisionedByCatalogId(catalogId))
                {
                    await env.Appx.DeprovisionPackageFamilyAsync(provisioned.PackageFamilyName, ct)
                        .ConfigureAwait(false);
                    if (!string.IsNullOrWhiteSpace(provisioned.PackageFamilyName))
                    {
                        families.Add(provisioned.PackageFamilyName);
                    }
                }

                env.ReportStatus(new SessionStatus(
                    $"removed.appx.online.{catalogId}",
                    $"Removed online AppX catalog id '{catalogId}'."));
            }

            foreach (string pfn in families)
            {
                env.Appx.EnsureDeprovisionedMark(pfn);
                env.ReportStatus(new SessionStatus(
                    $"deprovisioned.appx.{pfn}",
                    $"Ensured deprovisioned mark for '{pfn}'."));
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return FailJob(env, "jobs.failed", $"Job '{job.Id}': {ex.Message}");
        }

        return null;
    }
}

