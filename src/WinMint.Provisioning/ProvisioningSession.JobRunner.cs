namespace WinMint.Provisioning;

using System.Text.Json;
using WinMint.Contracts;

public static partial class ProvisioningSession
{
    private static partial class JobRunner
    {
        public static async Task<JobsPhaseResult> ExecuteAsync(
            ProvisioningBundle bundle,
            ShellEnvironment env,
            List<string> phases,
            long tenureStartTs,
            int startIndex,
            CancellationToken ct)
        {
            SessionStatus begin = new("jobs.begin", "Provisioning jobs start.");
            Note(env, phases, begin);

            List<PackageFailureEntry> packageFailures = [];

            JobsPhaseResult? RecordPackageFailure(ProvisionJob failingJob, string code, string message, int exitCode = 1)
            {
                if (!IsPackageKind(failingJob.Kind))
                {
                    return FailJob(env, phases, code, message);
                }

                if (bundle.PackageStrict)
                {
                    return FailJob(env, phases, code, message);
                }

                packageFailures.Add(
                    new PackageFailureEntry(failingJob.Id, failingJob.Kind.ToWire(), exitCode, message));
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

                string fileName;
                IReadOnlyList<string> arguments;
                switch (job.Kind)
                {
                    case ProvisionJobKind.AppxSafetyNet:
                        {
                            JobsPhaseResult? appxResult = await RunAppxSafetyNetJobAsync(bundle, env, phases, job, ct)
                                .ConfigureAwait(false);
                            if (appxResult is not null)
                            {
                                return appxResult.Value;
                            }

                            continue;
                        }

                    case ProvisionJobKind.OneDriveUninstall:
                        {
                            JobsPhaseResult? od = await RunOneDriveUninstallJobAsync(env, phases, job, ct)
                                .ConfigureAwait(false);
                            if (od is not null)
                            {
                                return od.Value;
                            }

                            continue;
                        }

                    case ProvisionJobKind.ReservedStorageDisable:
                        {
                            JobsPhaseResult? rs = await RunReservedStorageDisableJobAsync(env, phases, job, ct)
                                .ConfigureAwait(false);
                            if (rs is not null)
                            {
                                return rs.Value;
                            }

                            continue;
                        }

                    case ProvisionJobKind.WorkstationQuiet:
                        {
                            JobsPhaseResult? quiet = RunWorkstationQuietJob(env, phases, job);
                            if (quiet is not null)
                            {
                                return quiet.Value;
                            }

                            continue;
                        }

                    case ProvisionJobKind.DohSet:
                        {
                            JobsPhaseResult? doh = await RunDohSetJobAsync(env, phases, job, ct)
                                .ConfigureAwait(false);
                            if (doh is not null)
                            {
                                return doh.Value;
                            }

                            continue;
                        }

                    case ProvisionJobKind.PackageAuditNative:
                        {
                            JobsPhaseResult? audit = RunNativePackageAuditJob(env, phases, job, ct);
                            if (audit is not null)
                            {
                                return audit.Value;
                            }

                            continue;
                        }

                    case ProvisionJobKind.Stub:
                        fileName = "cmd.exe";
                        arguments = ["/c", "exit", "0"];
                        break;

                    case ProvisionJobKind.Winget:
                    case ProvisionJobKind.WingetImport:
                        {
                            if (job.Kind is ProvisionJobKind.Winget && string.IsNullOrWhiteSpace(job.PackageId))
                            {
                                return FailJob(
                                    env,
                                    phases,
                                    "jobs.failed",
                                    $"Job '{job.Id}' kind winget requires packageId.");
                            }

                            if (env.Appx is null)
                            {
                                return FailJob(
                                    env,
                                    phases,
                                    "jobs.failed",
                                    $"Job '{job.Id}' requires IAppxPackageManager.");
                            }

                            try
                            {
                                await env.Appx.RegisterPackageFamilyForCurrentUserAsync(
                                        DesktopAppInstallerFamilyName,
                                        ct)
                                    .ConfigureAwait(false);
                            }
                            catch (Exception ex) when (ex is not OperationCanceledException)
                            {
                                JobsPhaseResult? regFail = RecordPackageFailure(
                                    job,
                                    "jobs.winget.registerFailed",
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
                                    "jobs.winget.pathMissing",
                                    $"{job.Id}: winget.exe not found after registering {DesktopAppInstallerFamilyName}.");
                                if (pathFail is not null)
                                {
                                    return pathFail.Value;
                                }

                                continue;
                            }

                            fileName = resolvedWinget;

                            if (job.Kind is ProvisionJobKind.WingetImport)
                            {
                                if (!File.Exists(BundleLoader.DefaultGuestWingetImportPath))
                                {
                                    JobsPhaseResult? importFail = RecordPackageFailure(
                                        job,
                                        "jobs.winget.importMissing",
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

                            break;
                        }

                    case ProvisionJobKind.Scoop:
                    case ProvisionJobKind.ScoopBatch:
                        {
                            if (string.IsNullOrWhiteSpace(job.PackageId))
                            {
                                string kindWire = job.Kind.ToWire();
                                return FailJob(
                                    env,
                                    phases,
                                    "jobs.failed",
                                    $"Job '{job.Id}' kind {kindWire} requires packageId.");
                            }

                            if (env.ResolveScoopCmd is null)
                            {
                                return FailJob(
                                    env,
                                    phases,
                                    "jobs.failed",
                                    $"Job '{job.Id}' requires ResolveScoopCmd.");
                            }

                            (JobsPhaseResult? scoopReady, string? scoopCmd) = await EnsureScoopReadyAsync(
                                    env,
                                    job,
                                    RecordPackageFailure,
                                    ct)
                                .ConfigureAwait(false);
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
                                bool bucketsFailed = false;
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
                                        bucketAdd = await env.Processes.RunAsync(
                                                scoopCmd,
                                                ["bucket", "add", bucket],
                                                ct)
                                            .ConfigureAwait(false);
                                    }
                                    catch (Exception ex) when (ex is not OperationCanceledException)
                                    {
                                        JobsPhaseResult? bucketFail = RecordPackageFailure(
                                            job,
                                            "jobs.scoop.bucketFailed",
                                            $"{job.Id}: scoop bucket add {bucket}: {ex.Message}");
                                        if (bucketFail is not null)
                                        {
                                            return bucketFail.Value;
                                        }

                                        bucketsFailed = true;
                                        break;
                                    }

                                    if (bucketAdd.ExitCode != 0)
                                    {
                                        JobsPhaseResult? bucketFail = RecordPackageFailure(
                                            job,
                                            "jobs.scoop.bucketFailed",
                                            $"{job.Id}: scoop bucket add {bucket} exited {bucketAdd.ExitCode}.");
                                        if (bucketFail is not null)
                                        {
                                            return bucketFail.Value;
                                        }

                                        bucketsFailed = true;
                                        break;
                                    }
                                }

                                if (bucketsFailed)
                                {
                                    continue;
                                }
                            }

                            fileName = scoopCmd;
                            if (job.Kind is ProvisionJobKind.ScoopBatch)
                            {
                                string[] ids = job.PackageId.Split(
                                    ';',
                                    StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                                arguments = ["install", .. ids];
                            }
                            else
                            {
                                arguments = ["install", job.PackageId];
                            }

                            break;
                        }

                    case ProvisionJobKind.ShellStamp:
                        {
                            (bool stampOk, string message) = await ShellStamp.ApplyAsync(httpHandler: null, ct)
                                .ConfigureAwait(false);
                            if (!stampOk)
                            {
                                JobsPhaseResult? stampFail = RecordPackageFailure(
                                    job,
                                    "jobs.shell.stampFailed",
                                    $"{job.Id}: {message}");
                                if (stampFail is not null)
                                {
                                    return stampFail.Value;
                                }

                                continue;
                            }

                            SessionStatus stamped = new("jobs.shell.stamp", message);
                            Note(env, phases, stamped);
                            continue;
                        }

                    case ProvisionJobKind.Wsl:
                        {
                            if (string.IsNullOrWhiteSpace(job.PackageId))
                            {
                                return FailJob(
                                    env,
                                    phases,
                                    "jobs.failed",
                                    $"Job '{job.Id}' kind wsl requires packageId (distro name).");
                            }

                            if (job.WslInstallKind is WslInstallKind.FromFile)
                            {
                                JobsPhaseResult? fromFile = await RunWslFromFileInstallAsync(env, phases, job, ct)
                                    .ConfigureAwait(false);
                                if (fromFile is not null)
                                {
                                    return fromFile.Value;
                                }

                                if (job.NeedsReboot)
                                {
                                    return RequestJobReboot(env, phases, job, i + 1);
                                }

                                continue;
                            }

                            SuppressWslOobe(env);

                            fileName = "wsl.exe";
                            arguments =
                            [
                                "--install",
                                "-d",
                                job.PackageId,
                                "--no-launch",
                            ];
                            break;
                        }

                    case ProvisionJobKind.WslPlatform:
                        {
                            JobsPhaseResult? platform = await RunWslPlatformJobAsync(env, phases, job, i, ct)
                                .ConfigureAwait(false);
                            if (platform is not null)
                            {
                                return platform.Value;
                            }

                            continue;
                        }

                    default:
                        return FailJob(
                            env,
                            phases,
                            "jobs.kind.unsupported",
                            $"Unsupported job kind '{job.Kind.ToWire()}' for id '{job.Id}'.");
                }

                ProcessStartResult started;
                try
                {
                    started = await env.Processes.RunAsync(fileName, arguments, ct).ConfigureAwait(false);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    JobsPhaseResult? spawnFail = RecordPackageFailure(
                        job,
                        "jobs.spawnFailed",
                        $"{job.Id}: {ex.Message}");
                    if (spawnFail is not null)
                    {
                        return spawnFail.Value;
                    }

                    continue;
                }

                if (started.ExitCode != 0)
                {
                    // Microsoft Dev Config: ERROR_SUCCESS_REBOOT_REQUIRED (3010) / ERROR_SUCCESS_REBOOT_INITIATED (1641).
                    if (job.Kind is ProvisionJobKind.Wsl
                        && Win32WslPlatform.IsRebootRequiredExitCode(started.ExitCode))
                    {
                        return RequestJobReboot(env, phases, job, i + 1);
                    }

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
                    return RequestJobReboot(env, phases, job, i + 1);
                }
            }

            WritePackagesEvidence(env.EvidenceDirectory, packageFailures);

            string okMessage = packageFailures.Count > 0
                ? $"Provisioning jobs completed with {packageFailures.Count} package failure(s)."
                : "Provisioning jobs completed.";
            SessionStatus ok = new("jobs.ok", okMessage);
            Note(env, phases, ok);
            return new JobsPhaseResult(SessionOutcome.Complete, ok, TimedOut: false);
        }



        /// <summary>Paint the failure, log the phase, and end the jobs phase — the only way a job fails.</summary>
        private static JobsPhaseResult FailJob(
            ShellEnvironment env,
            List<string> phases,
            string code,
            string message)
        {
            SessionStatus status = new(code, message);
            Note(env, phases, status);
            return new JobsPhaseResult(SessionOutcome.Failed, status, TimedOut: false);
        }

        private static JobsPhaseResult RequestJobReboot(
            ShellEnvironment env,
            List<string> phases,
            ProvisionJob job,
            int nextJobIndex)
        {
            CheckpointState checkpoint = new($"jobs:{nextJobIndex}");
            env.Checkpoints.WriteCheckpoint(checkpoint);
            env.Checkpoints.WriteHeartbeat(env.Time.GetUtcNow());
            SessionStatus reboot = new(
                "jobs.reboot",
                $"Job '{job.Id}' requires reboot; checkpoint {checkpoint.Phase}.");
            Note(env, phases, reboot);
            return new JobsPhaseResult(SessionOutcome.Reboot, reboot, TimedOut: false);
        }



        public static async Task<JobsPhaseResult?> EnsureNetworkAvailableAsync(
            ProvisioningBundle bundle,
            ShellEnvironment env,
            List<string> phases,
            CancellationToken ct)
        {
            if (env.Connectivity is not null
                && await env.Connectivity.HasOutboundNetworkAsync(ct).ConfigureAwait(false))
            {
                SessionStatus ok = new("network.ok", "Outbound connectivity available.");
                Note(env, phases, ok);
                return null;
            }

            return FailJob(
                env,
                phases,
                "network.required.offline",
                "Plan requires network but outbound connectivity probe failed.");
        }



        private static bool IsPackageKind(ProvisionJobKind kind) => kind is
            ProvisionJobKind.Winget
            or ProvisionJobKind.WingetImport
            or ProvisionJobKind.Scoop
            or ProvisionJobKind.ScoopBatch
            or ProvisionJobKind.ShellStamp;



        private static void WritePackagesEvidence(string? evidenceDirectory, List<PackageFailureEntry> failures)
        {
            if (failures.Count == 0 || string.IsNullOrWhiteSpace(evidenceDirectory))
            {
                return;
            }

            Directory.CreateDirectory(evidenceDirectory);
            string path = Path.Combine(evidenceDirectory, "packages.evidence.json");
            PackagesEvidenceFile doc = new(PackagesEvidenceSchemaVersion, failures);
            byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(doc, ProvisioningJsonContext.Default.PackagesEvidenceFile);
            File.WriteAllBytes(path, bytes);
        }
    }
}

