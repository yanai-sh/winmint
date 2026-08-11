namespace WinMint.Provisioning;

public static partial class ProvisioningSession
{
    private static partial class JobRunner
    {
        private static async Task<JobsPhaseResult?> RunOneDriveUninstallJobAsync(
            SessionEnvironment env,
            List<string> phases,
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
                SessionStatus failed = new("jobs.failed", $"{job.Id}: {ex.Message}");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }
        }

        private static JobsPhaseResult? RunWorkstationQuietJob(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job)
        {
            try
            {
                (env.ApplyWorkstationQuiet ?? Win32WorkstationQuiet.Apply)();
                SessionStatus ok = new("jobs.workstation.quiet", "Dark theme and quiet user defaults applied.");
                env.Splash.SetStatus(ok);
                phases.Add(ok.Code);
                return null;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus failed = new("jobs.failed", $"{job.Id}: {ex.Message}");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }
        }

        private static async Task<JobsPhaseResult?> RunReservedStorageDisableJobAsync(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            try
            {
                ProcessStartResult started = await env.Processes.RunAsync(
                        "dism.exe",
                        ["/Online", "/Set-ReservedStorageState", "/State:Disabled"],
                        ct)
                    .ConfigureAwait(false);
                if (started.ExitCode != 0)
                {
                    SessionStatus failed = new(
                        "jobs.failed",
                        $"{job.Id}: dism Set-ReservedStorageState exited {started.ExitCode}.");
                    env.Splash.SetStatus(failed);
                    phases.Add(failed.Code);
                    return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
                }

                return null;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus failed = new("jobs.failed", $"{job.Id}: {ex.Message}");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }
        }

        private static async Task<JobsPhaseResult?> RunDohSetJobAsync(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            // Plan-emitted params only — no guest DoH provider table (ProductPosture owns the catalog).
            if (string.IsNullOrWhiteSpace(job.DohPrimary)
                || string.IsNullOrWhiteSpace(job.DohSecondary)
                || string.IsNullOrWhiteSpace(job.DohTemplate))
            {
                SessionStatus bad = new(
                    "jobs.failed",
                    $"Job '{job.Id}' kind doh.set requires dohPrimary/dohSecondary/dohTemplate from the plan.");
                env.Splash.SetStatus(bad);
                phases.Add(bad.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, bad, TimedOut: false);
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
                    SessionStatus failed = new(
                        "jobs.failed",
                        $"{job.Id}: DoH configure exited {started.ExitCode}.");
                    env.Splash.SetStatus(failed);
                    phases.Add(failed.Code);
                    return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
                }

                return null;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus failed = new("jobs.failed", $"{job.Id}: {ex.Message}");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }
        }

        private static async Task<JobsPhaseResult?> RunAppxSafetyNetJobAsync(
            ProvisioningBundle bundle,
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            if (env.Appx is null)
            {
                SessionStatus missing = new(
                    "jobs.failed",
                    $"Job '{job.Id}' requires IAppxPackageManager.");
                env.Splash.SetStatus(missing);
                phases.Add(missing.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, missing, TimedOut: false);
            }

            IReadOnlyList<string> ids = bundle.RemoveProvisionedAppx ?? [];
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

                    phases.Add($"removed.appx.online.{catalogId}");
                }

                foreach (string pfn in families)
                {
                    env.Appx.EnsureDeprovisionedMark(pfn);
                    phases.Add($"deprovisioned.appx.{pfn}");
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus failed = new("jobs.failed", $"Job '{job.Id}': {ex.Message}");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }

            return null;
        }
    }
}

