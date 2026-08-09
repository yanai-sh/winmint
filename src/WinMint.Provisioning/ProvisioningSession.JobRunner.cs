namespace WinMint.Provisioning;

using System.Net.Http.Json;
using System.Reflection.PortableExecutable;
using System.Text.Json;

public static partial class ProvisioningSession
{
    private static class JobRunner
    {
        public static JobsPhaseResult Execute(
            ProvisioningBundle bundle,
            SessionEnvironment env,
            List<string> phases,
            long tenureStartTs,
            int startIndex,
            CancellationToken ct)
        {
            JobsPhaseResult FailJob(string code, string message)
            {
                SessionStatus status = new(code, message);
                env.Splash.SetStatus(status);
                phases.Add(status.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, status, TimedOut: false);
            }

            SessionStatus begin = new("jobs.begin", "Provisioning jobs start.");
            env.Splash.SetStatus(begin);
            phases.Add(begin.Code);

            List<PackageFailureEntry> packageFailures = [];

            JobsPhaseResult? RecordPackageFailure(ProvisionJob failingJob, string code, string message, int exitCode = 1)
            {
                if (!IsPackageKind(failingJob.Kind))
                {
                    return FailJob(code, message);
                }

                if (bundle.PackageStrict)
                {
                    return FailJob(code, message);
                }

                packageFailures.Add(new PackageFailureEntry(failingJob.Id, failingJob.Kind, exitCode, message));
                return null;
            }

            for (int i = startIndex; i < bundle.Jobs.Count; i++)
            {
                ProvisionJob job = bundle.Jobs[i];
                if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
                {
                    return new JobsPhaseResult(SessionOutcome.Failed, TimeoutStatus(), TimedOut: true);
                }

                ct.ThrowIfCancellationRequested();

                if (string.Equals(job.Kind, "appx.safetyNet", StringComparison.OrdinalIgnoreCase))
                {
                    JobsPhaseResult? appxResult = RunAppxSafetyNetJob(bundle, env, phases, job);
                    if (appxResult is not null)
                    {
                        return appxResult.Value;
                    }

                    continue;
                }

                if (string.Equals(job.Kind, "onedrive.uninstall", StringComparison.OrdinalIgnoreCase))
                {
                    JobsPhaseResult? od = RunOneDriveUninstallJob(env, phases, job, ct);
                    if (od is not null)
                    {
                        return od.Value;
                    }

                    continue;
                }

                if (string.Equals(job.Kind, "reservedStorage.disable", StringComparison.OrdinalIgnoreCase))
                {
                    JobsPhaseResult? rs = RunReservedStorageDisableJob(env, phases, job, ct);
                    if (rs is not null)
                    {
                        return rs.Value;
                    }

                    continue;
                }

                if (string.Equals(job.Kind, "doh.set", StringComparison.OrdinalIgnoreCase))
                {
                    JobsPhaseResult? doh = RunDohSetJob(env, phases, job, ct);
                    if (doh is not null)
                    {
                        return doh.Value;
                    }

                    continue;
                }

                if (string.Equals(job.Kind, "package.auditNative", StringComparison.OrdinalIgnoreCase))
                {
                    JobsPhaseResult? audit = RunNativePackageAuditJob(env, phases, job, ct);
                    if (audit is not null)
                    {
                        return audit.Value;
                    }

                    continue;
                }

                string fileName;
                IReadOnlyList<string> arguments;
                if (string.Equals(job.Kind, "stub", StringComparison.OrdinalIgnoreCase))
                {
                    fileName = "cmd.exe";
                    arguments = ["/c", "exit", "0"];
                }
                else if (string.Equals(job.Kind, "winget", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(job.Kind, "winget.import", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.Equals(job.Kind, "winget", StringComparison.OrdinalIgnoreCase)
                        && string.IsNullOrWhiteSpace(job.PackageId))
                    {
                        return FailJob("jobs.failed", $"Job '{job.Id}' kind winget requires packageId.");
                    }

                    if (env.Appx is null)
                    {
                        return FailJob("jobs.failed", $"Job '{job.Id}' requires IAppxPackageManager.");
                    }

                    try
                    {
                        env.Appx.RegisterPackageFamilyForCurrentUser(DesktopAppInstallerFamilyName);
                    }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        JobsPhaseResult? regFail = RecordPackageFailure(
                            job,
                            "jobs.winget.register_failed",
                            $"{job.Id}: register {DesktopAppInstallerFamilyName}: {ex.Message}");
                        if (regFail is not null)
                        {
                            return regFail.Value;
                        }

                        continue;
                    }

                    string? resolvedWinget = env.Appx.TryResolveWingetExecutablePath();
                    if (string.IsNullOrWhiteSpace(resolvedWinget))
                    {
                        JobsPhaseResult? pathFail = RecordPackageFailure(
                            job,
                            "jobs.winget.path_missing",
                            $"{job.Id}: winget.exe not found after registering {DesktopAppInstallerFamilyName}.");
                        if (pathFail is not null)
                        {
                            return pathFail.Value;
                        }

                        continue;
                    }

                    fileName = resolvedWinget;

                    if (string.Equals(job.Kind, "winget.import", StringComparison.OrdinalIgnoreCase))
                    {
                        if (!File.Exists(BundleLoader.DefaultGuestWingetImportPath))
                        {
                            JobsPhaseResult? importFail = RecordPackageFailure(
                                job,
                                "jobs.winget.import_missing",
                                $"{job.Id}: winget-import.json missing at {BundleLoader.DefaultGuestWingetImportPath}.");
                            if (importFail is not null)
                            {
                                return importFail.Value;
                            }

                            continue;
                        }

                        arguments =
                        [
                            "import",
                            "--import-file",
                            BundleLoader.DefaultGuestWingetImportPath,
                            "--accept-package-agreements",
                            "--accept-source-agreements",
                            "--disable-interactivity",
                        ];
                    }
                    else
                    {
                        arguments =
                        [
                            "install",
                            "--id",
                            job.PackageId!,
                            "--exact",
                            "--silent",
                            "--accept-package-agreements",
                            "--accept-source-agreements",
                            "--disable-interactivity",
                        ];
                        if (!string.IsNullOrWhiteSpace(job.WingetArchitecture))
                        {
                            arguments = [.. arguments, "--architecture", job.WingetArchitecture];
                        }
                    }
                }
                else if (string.Equals(job.Kind, "scoop", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(job.Kind, "scoop.batch", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.Equals(job.Kind, "scoop", StringComparison.OrdinalIgnoreCase)
                        && string.IsNullOrWhiteSpace(job.PackageId))
                    {
                        return FailJob("jobs.failed", $"Job '{job.Id}' kind scoop requires packageId.");
                    }

                    if (string.Equals(job.Kind, "scoop.batch", StringComparison.OrdinalIgnoreCase)
                        && string.IsNullOrWhiteSpace(job.PackageId))
                    {
                        return FailJob("jobs.failed", $"Job '{job.Id}' kind scoop.batch requires packageId.");
                    }

                    if (env.ResolveScoopCmd is null)
                    {
                        return FailJob("jobs.failed", $"Job '{job.Id}' requires ResolveScoopCmd.");
                    }

                    JobsPhaseResult? scoopReady = EnsureScoopReady(env, job, RecordPackageFailure, ct, out string? scoopCmd);
                    if (scoopReady is not null)
                    {
                        return scoopReady.Value;
                    }

                    if (scoopCmd is null)
                    {
                        continue;
                    }

                    if (job.ScoopBuckets is { Count: > 0 })
                    {
                        foreach (string bucket in job.ScoopBuckets)
                        {
                            if (string.IsNullOrWhiteSpace(bucket)
                                || string.Equals(bucket, "main", StringComparison.OrdinalIgnoreCase))
                            {
                                continue;
                            }

                            ProcessStartResult bucketAdd;
                            try
                            {
                                bucketAdd = env.Processes.Run(scoopCmd, ["bucket", "add", bucket], ct);
                            }
                            catch (Exception ex) when (ex is not OperationCanceledException)
                            {
                                JobsPhaseResult? bucketFail = RecordPackageFailure(
                                    job,
                                    "jobs.scoop.bucket_failed",
                                    $"{job.Id}: scoop bucket add {bucket}: {ex.Message}");
                                if (bucketFail is not null)
                                {
                                    return bucketFail.Value;
                                }

                                goto ScoopBucketsFailed;
                            }

                            if (bucketAdd.ExitCode != 0)
                            {
                                JobsPhaseResult? bucketFail = RecordPackageFailure(
                                    job,
                                    "jobs.scoop.bucket_failed",
                                    $"{job.Id}: scoop bucket add {bucket} exited {bucketAdd.ExitCode}.");
                                if (bucketFail is not null)
                                {
                                    return bucketFail.Value;
                                }

                                goto ScoopBucketsFailed;
                            }
                        }
                    }

                    fileName = scoopCmd;
                    if (string.Equals(job.Kind, "scoop.batch", StringComparison.OrdinalIgnoreCase))
                    {
                        string[] ids = job.PackageId!.Split(
                            ';',
                            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                        arguments = ["install", .. ids];
                    }
                    else
                    {
                        arguments = ["install", job.PackageId!];
                    }

                    goto ScoopRun;

                ScoopBucketsFailed:
                    continue;

                ScoopRun:
                    ;
                }
                else if (string.Equals(job.Kind, "wsl", StringComparison.OrdinalIgnoreCase))
                {
                    if (string.IsNullOrWhiteSpace(job.PackageId))
                    {
                        return FailJob(
                            "jobs.failed",
                            $"Job '{job.Id}' kind wsl requires packageId (distro name).");
                    }

                    if (string.Equals(job.WslInstallKind, "fromFile", StringComparison.OrdinalIgnoreCase))
                    {
                        JobsPhaseResult? fromFile = RunWslFromFileInstall(env, phases, job, ct);
                        if (fromFile is not null)
                        {
                            return fromFile.Value;
                        }

                        if (job.NeedsReboot)
                        {
                            int nextIndex = i + 1;
                            CheckpointState checkpoint = new($"jobs:{nextIndex}");
                            env.Checkpoints.WriteCheckpoint(checkpoint);
                            env.Checkpoints.WriteHeartbeat(env.Time.GetUtcNow());
                            SessionStatus reboot = new(
                                "jobs.reboot",
                                $"Job '{job.Id}' requires reboot; checkpoint {checkpoint.Phase}.");
                            env.Splash.SetStatus(reboot);
                            phases.Add(reboot.Code);
                            return new JobsPhaseResult(SessionOutcome.Reboot, reboot, TimedOut: false);
                        }

                        continue;
                    }

                    fileName = "wsl.exe";
                    arguments =
                    [
                        "--install",
                        "-d",
                        job.PackageId,
                        "--no-launch",
                    ];
                }
                else
                {
                    return FailJob(
                        "jobs.kind.unsupported",
                        $"Unsupported job kind '{job.Kind}' for id '{job.Id}'.");
                }

                ProcessStartResult started;
                try
                {
                    started = env.Processes.Run(fileName, arguments, ct);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    JobsPhaseResult? spawnFail = RecordPackageFailure(
                        job,
                        "jobs.spawn_failed",
                        $"{job.Id}: {ex.Message}");
                    if (spawnFail is not null)
                    {
                        return spawnFail.Value;
                    }

                    continue;
                }

                if (started.ExitCode != 0)
                {
                    JobsPhaseResult? runFail = RecordPackageFailure(
                        job,
                        "jobs.failed",
                        $"Job '{job.Id}' exited {started.ExitCode}.",
                        started.ExitCode);
                    if (runFail is not null)
                    {
                        return runFail.Value;
                    }

                    continue;
                }

                if (job.NeedsReboot)
                {
                    int nextIndex = i + 1;
                    CheckpointState checkpoint = new($"jobs:{nextIndex}");
                    env.Checkpoints.WriteCheckpoint(checkpoint);
                    env.Checkpoints.WriteHeartbeat(env.Time.GetUtcNow());
                    SessionStatus reboot = new(
                        "jobs.reboot",
                        $"Job '{job.Id}' requires reboot; checkpoint {checkpoint.Phase}.");
                    env.Splash.SetStatus(reboot);
                    phases.Add(reboot.Code);
                    return new JobsPhaseResult(SessionOutcome.Reboot, reboot, TimedOut: false);
                }
            }

            WritePackagesEvidence(env.EvidenceDirectory, packageFailures);

            string okMessage = packageFailures.Count > 0
                ? $"Provisioning jobs completed with {packageFailures.Count} package failure(s)."
                : "Provisioning jobs completed.";
            SessionStatus ok = new("jobs.ok", okMessage);
            env.Splash.SetStatus(ok);
            phases.Add(ok.Code);
            return new JobsPhaseResult(SessionOutcome.Complete, ok, TimedOut: false);
        }

        /// <summary>
        /// KEEPFLAG safety net: RemovePackage for registered matches; Deprovision only if still provisioned.
        /// </summary>
        /// <returns>Failure result, or null when the job succeeded (caller continues the loop).</returns>
        private static JobsPhaseResult? RunOneDriveUninstallJob(
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
                ProcessStartResult started = env.Processes.Run(setup, ["/uninstall", "/allusers"], ct);
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

        private static JobsPhaseResult? RunReservedStorageDisableJob(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            try
            {
                ProcessStartResult started = env.Processes.Run(
                    "dism.exe",
                    ["/Online", "/Set-ReservedStorageState", "/State:Disabled"],
                    ct);
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

        private static JobsPhaseResult? RunDohSetJob(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            // Plan-emitted params only — no guest DoH provider table (ProductOfflinePolicies owns the catalog).
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
                ProcessStartResult started = env.Processes.Run(
                    "powershell.exe",
                    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
                    ct);
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

        private static JobsPhaseResult? RunAppxSafetyNetJob(
            ProvisioningBundle bundle,
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job)
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
                foreach (string catalogId in ids)
                {
                    if (string.IsNullOrWhiteSpace(catalogId))
                    {
                        continue;
                    }

                    foreach (AppxPackageInfo registered in env.Appx.FindRegisteredByCatalogId(catalogId))
                    {
                        env.Appx.RemovePackage(registered.PackageFullName);
                    }

                    foreach (AppxPackageInfo provisioned in env.Appx.FindProvisionedByCatalogId(catalogId))
                    {
                        env.Appx.DeprovisionPackageFamily(provisioned.PackageFamilyName);
                    }

                    phases.Add($"removed.appx.online.{catalogId}");
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

        public static JobsPhaseResult? EnsureNetworkAvailable(
            ProvisioningBundle bundle,
            SessionEnvironment env,
            List<string> phases)
        {
            if (env.Connectivity?.HasOutboundNetwork() == true)
            {
                SessionStatus ok = new("network.ok", "Outbound connectivity available.");
                env.Splash.SetStatus(ok);
                phases.Add(ok.Code);
                return null;
            }

            SessionStatus failed = new(
                "network.required.offline",
                "Plan requires network but outbound connectivity probe failed.");
            env.Splash.SetStatus(failed);
            phases.Add(failed.Code);
            return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
        }
        private static JobsPhaseResult? RunWslFromFileInstall(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            if (string.IsNullOrWhiteSpace(job.WslFromFileRepo)
                || job.WslFromFileAssetNames is not { Count: > 0 })
            {
                SessionStatus bad = new("jobs.failed", $"{job.Id}: fromFile WSL requires repo and asset names.");
                env.Splash.SetStatus(bad);
                phases.Add(bad.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, bad, TimedOut: false);
            }

            string? assetPath;
            try
            {
                assetPath = DownloadWslFromFileAsset(job.WslFromFileRepo, job.WslFromFileAssetNames, ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus failed = new("jobs.wsl.fromFile_download_failed", $"{job.Id}: {ex.Message}");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }

            if (assetPath is null)
            {
                SessionStatus failed = new(
                    "jobs.wsl.fromFile_asset_missing",
                    $"{job.Id}: no matching GitHub release asset for {job.WslFromFileRepo}.");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }

            try
            {
                ProcessStartResult started = env.Processes.Run(
                    "wsl.exe",
                    ["--install", "--from-file", assetPath, "--no-launch"],
                    ct);
                if (started.ExitCode != 0)
                {
                    SessionStatus failed = new("jobs.failed", $"{job.Id}: wsl --from-file exited {started.ExitCode}.");
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

        private static string? DownloadWslFromFileAsset(
            string repo,
            IReadOnlyList<string> assetNameHints,
            CancellationToken ct)
        {
            using HttpClient client = new();
            client.DefaultRequestHeaders.UserAgent.ParseAdd("WinMint-Provisioning/1.0");
            string url = $"https://api.github.com/repos/{repo}/releases/latest";
            using HttpResponseMessage response = client.GetAsync(url, ct).GetAwaiter().GetResult();
            response.EnsureSuccessStatusCode();
            GitHubRelease? release = response.Content.ReadFromJsonAsync(
                GitHubReleaseJsonContext.Default.GitHubRelease,
                ct).GetAwaiter().GetResult();
            if (release?.Assets is null)
            {
                return null;
            }

            foreach (string hint in assetNameHints)
            {
                GitHubAsset? asset = release.Assets.FirstOrDefault(
                    a => a.Name.Contains(hint, StringComparison.OrdinalIgnoreCase));
                if (asset?.BrowserDownloadUrl is null)
                {
                    continue;
                }

                string tempDir = Path.Combine(Path.GetTempPath(), "WinMint", "wsl");
                Directory.CreateDirectory(tempDir);
                string dest = Path.Combine(tempDir, asset.Name);
                using HttpResponseMessage assetResponse = client.GetAsync(asset.BrowserDownloadUrl, ct).GetAwaiter().GetResult();
                assetResponse.EnsureSuccessStatusCode();
                using FileStream stream = File.Create(dest);
                assetResponse.Content.CopyToAsync(stream, ct).GetAwaiter().GetResult();
                return dest;
            }

            return null;
        }

        private static bool IsPackageKind(string kind) =>
            string.Equals(kind, "winget", StringComparison.OrdinalIgnoreCase)
            || string.Equals(kind, "winget.import", StringComparison.OrdinalIgnoreCase)
            || string.Equals(kind, "scoop", StringComparison.OrdinalIgnoreCase)
            || string.Equals(kind, "scoop.batch", StringComparison.OrdinalIgnoreCase);

        private static JobsPhaseResult? EnsureScoopReady(
            SessionEnvironment env,
            ProvisionJob job,
            Func<ProvisionJob, string, string, int, JobsPhaseResult?> recordFailure,
            CancellationToken ct,
            out string? scoopCmd)
        {
            scoopCmd = env.ResolveScoopCmd!();
            if (scoopCmd is not null)
            {
                return null;
            }

            ProcessStartResult bootstrap;
            try
            {
                bootstrap = env.Processes.Run(
                    "powershell.exe",
                    [
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-Command",
                        """iex "& {$(irm get.scoop.sh)} -RunAsAdmin"; exit $LASTEXITCODE""",
                    ],
                    ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                JobsPhaseResult? fail = recordFailure(
                    job,
                    "jobs.scoop.bootstrap_failed",
                    $"{job.Id}: scoop bootstrap spawn: {ex.Message}",
                    1);
                scoopCmd = null;
                return fail;
            }

            if (bootstrap.ExitCode != 0)
            {
                JobsPhaseResult? fail = recordFailure(
                    job,
                    "jobs.scoop.bootstrap_failed",
                    $"{job.Id}: scoop bootstrap exited {bootstrap.ExitCode} (network required).",
                    bootstrap.ExitCode);
                scoopCmd = null;
                return fail;
            }

            scoopCmd = env.ResolveScoopCmd!();
            if (scoopCmd is null)
            {
                JobsPhaseResult? fail = recordFailure(
                    job,
                    "jobs.scoop.bootstrap_failed",
                    $"{job.Id}: scoop.cmd missing after bootstrap.",
                    1);
                return fail;
            }

            return null;
        }

        private static void WritePackagesEvidence(string? evidenceDirectory, List<PackageFailureEntry> failures)
        {
            if (failures.Count == 0 || string.IsNullOrWhiteSpace(evidenceDirectory))
            {
                return;
            }

            Directory.CreateDirectory(evidenceDirectory);
            string path = Path.Combine(evidenceDirectory, "packages.evidence.json");
            PackagesEvidenceDocument doc = new(PackagesEvidenceSchemaVersion, failures);
            byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(doc, ProvisioningJsonContext.Default.PackagesEvidenceDocument);
            File.WriteAllBytes(path, bytes);
        }

        private static JobsPhaseResult? RunNativePackageAuditJob(
            SessionEnvironment env,
            List<string> phases,
            ProvisionJob job,
            CancellationToken ct)
        {
            _ = ct;
            if (string.IsNullOrWhiteSpace(job.PackageId))
            {
                SessionStatus bad = new("jobs.failed", $"{job.Id}: audit requires packageId list.");
                env.Splash.SetStatus(bad);
                phases.Add(bad.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, bad, TimedOut: false);
            }

            List<NativePackageAuditEntry> entries = [];
            bool anyNonNative = false;
            foreach (string installId in job.PackageId.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                bool found = false;
                foreach (string path in GuessGuiBinaryPaths(installId))
                {
                    if (!File.Exists(path))
                    {
                        continue;
                    }

                    found = true;
                    bool native = IsArm64NativeBinary(path);
                    entries.Add(new NativePackageAuditEntry(installId, path, native));
                    if (!native)
                    {
                        anyNonNative = true;
                    }

                    break;
                }

                if (!found)
                {
                    entries.Add(new NativePackageAuditEntry(installId, null, null));
                }
            }

            string evidenceDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "WinMint",
                "evidence");
            Directory.CreateDirectory(evidenceDir);
            string evidencePath = Path.Combine(evidenceDir, "native-packages.json");
            NativePackageAuditDocument doc = new("winmint.native-packages/v1", entries);
            File.WriteAllText(
                evidencePath,
                JsonSerializer.Serialize(doc, NativePackageAuditJsonContext.Default.NativePackageAuditDocument));

            if (job.AuditStrict && anyNonNative)
            {
                SessionStatus failed = new(
                    "jobs.package.audit_non_native",
                    $"{job.Id}: one or more winget GUI binaries are not native ARM64 (see {evidencePath}).");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed, TimedOut: false);
            }

            return null;
        }

        private static IEnumerable<string> GuessGuiBinaryPaths(string wingetId)
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            return wingetId switch
            {
                "Anysphere.Cursor" =>
                [
                    Path.Combine(localAppData, "Programs", "cursor", "Cursor.exe"),
                    Path.Combine(localAppData, "Programs", "Cursor", "Cursor.exe"),
                ],
                "Zen-Team.Zen-Browser" =>
                [
                    Path.Combine(programFiles, "Zen Browser", "zen.exe"),
                    Path.Combine(localAppData, "Zen Browser", "zen.exe"),
                ],
                "Brave.Brave" =>
                [
                    Path.Combine(programFiles, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
                    Path.Combine(localAppData, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"),
                ],
                "Microsoft.VisualStudioCode" =>
                [
                    Path.Combine(localAppData, "Programs", "Microsoft VS Code", "Code.exe"),
                    Path.Combine(programFiles, "Microsoft VS Code", "Code.exe"),
                ],
                "ZedIndustries.Zed" =>
                [
                    Path.Combine(localAppData, "Programs", "Zed", "Zed.exe"),
                    Path.Combine(programFiles, "Zed", "Zed.exe"),
                ],
                _ => [],
            };
        }

        private static bool IsArm64NativeBinary(string path)
        {
            using FileStream stream = File.OpenRead(path);
            PEReader reader = new(stream);
            return reader.PEHeaders.CoffHeader.Machine == Machine.Arm64;
        }
    }
}
