namespace WinMint.Provisioning;

using WinMint.Contracts;

internal sealed record JobRunnerEnv(
    IReadOnlyList<string> RemoveProvisionedAppx,
    IProcessHost Processes,
    TimeProvider Time,
    Action<SessionStatus> ReportStatus,
    IEvidenceSink Evidence,
    bool PackageStrict,
    TimeSpan WallClockTimeout,
    long TenureStartTimestamp,
    int StartIndex,
    IAppxPackageManager? Appx,
    Func<string?>? ResolveScoopCmd,
    IAssetDownload? AssetDownload,
    Func<bool> IsWslPlatformReady,
    Action ApplyWorkstationQuiet,
    Action SuppressWslOobe);

internal enum JobsRunKind
{
    Completed,
    Failed,
    NeedsReboot,
    TimedOut,
}

internal readonly record struct JobsRunResult(
    JobsRunKind Kind,
    SessionStatus Status,
    int? NextJobIndex = null);

internal static partial class ProvisioningJobRunner
{
    internal static async Task<JobsRunResult> Run(
        IReadOnlyList<ProvisionJob> jobs,
        JobRunnerEnv env,
        CancellationToken ct = default)
    {
        SessionStatus begin = new("jobs.begin", "Provisioning jobs start.");
        env.ReportStatus(begin);

        List<PackageFailureEntry> packageFailures = [];

        for (int i = env.StartIndex; i < jobs.Count; i++)
        {
            ProvisionJob job = jobs[i];
            JobContext context = new(env, packageFailures, job, i);
            if (env.Time.GetElapsedTime(env.TenureStartTimestamp) >= env.WallClockTimeout)
            {
                return new JobsRunResult(
                    JobsRunKind.TimedOut,
                    new SessionStatus("shell.timeout", "Shell tenure timeout."));
            }

            ct.ThrowIfCancellationRequested();

            string fileName;
            IReadOnlyList<string> arguments;
            switch (job.Kind)
            {
                case ProvisionJobKind.AppxSafetyNet:
                    {
                        JobsRunResult? appxResult = await RunAppxSafetyNetJobAsync(env, job, ct)
                            .ConfigureAwait(false);
                        if (appxResult is not null)
                        {
                            return appxResult.Value;
                        }

                        continue;
                    }

                case ProvisionJobKind.OneDriveUninstall:
                    {
                        JobsRunResult? od = await RunOneDriveUninstallJobAsync(env, job, ct)
                            .ConfigureAwait(false);
                        if (od is not null)
                        {
                            return od.Value;
                        }

                        continue;
                    }

                case ProvisionJobKind.ReservedStorageDisable:
                    {
                        JobsRunResult? rs = await RunReservedStorageDisableJobAsync(env, job, ct)
                            .ConfigureAwait(false);
                        if (rs is not null)
                        {
                            return rs.Value;
                        }

                        continue;
                    }

                case ProvisionJobKind.WorkstationQuiet:
                    {
                        JobsRunResult? quiet = RunWorkstationQuietJob(env, job);
                        if (quiet is not null)
                        {
                            return quiet.Value;
                        }

                        continue;
                    }

                case ProvisionJobKind.DohSet:
                    {
                        JobsRunResult? doh = await RunDohSetJobAsync(env, job, ct)
                            .ConfigureAwait(false);
                        if (doh is not null)
                        {
                            return doh.Value;
                        }

                        continue;
                    }

                case ProvisionJobKind.PackageAuditNative:
                    {
                        JobsRunResult? audit = RunNativePackageAuditJob(env, job, ct);
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
                                "jobs.failed",
                                $"Job '{job.Id}' kind winget requires packageId.");
                        }

                        if (env.Appx is null)
                        {
                            return FailJob(
                                env,
                                "jobs.failed",
                                $"Job '{job.Id}' requires IAppxPackageManager.");
                        }

                        try
                        {
                            await env.Appx.RegisterPackageFamilyForCurrentUserAsync(
                                    ProvisioningSession.DesktopAppInstallerFamilyName,
                                    ct)
                                .ConfigureAwait(false);
                        }
                        catch (Exception ex) when (ex is not OperationCanceledException)
                        {
                            JobsRunResult? regFail = context.RecordPackageFailure(
                                "jobs.winget.registerFailed",
                                $"{job.Id}: register {ProvisioningSession.DesktopAppInstallerFamilyName}: {ex.Message}");
                            if (regFail is not null)
                            {
                                return regFail.Value;
                            }

                            continue;
                        }

                        string? resolvedWinget = env.Appx.TryResolveWingetExecutablePath();
                        if (string.IsNullOrWhiteSpace(resolvedWinget))
                        {
                            JobsRunResult? pathFail = context.RecordPackageFailure(
                                "jobs.winget.pathMissing",
                                $"{job.Id}: winget.exe not found after registering {ProvisioningSession.DesktopAppInstallerFamilyName}.");
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
                                JobsRunResult? importFail = context.RecordPackageFailure(
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
                                "jobs.failed",
                                $"Job '{job.Id}' kind {kindWire} requires packageId.");
                        }

                        if (env.ResolveScoopCmd is null)
                        {
                            return FailJob(
                                env,
                                "jobs.failed",
                                $"Job '{job.Id}' requires ResolveScoopCmd.");
                        }

                        (JobsRunResult? scoopReady, string? scoopCmd) = await EnsureScoopReadyAsync(context, ct)
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
                                    JobsRunResult? bucketFail = context.RecordPackageFailure(
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
                                    JobsRunResult? bucketFail = context.RecordPackageFailure(
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
                            JobsRunResult? stampFail = context.RecordPackageFailure(
                                "jobs.shell.stampFailed",
                                $"{job.Id}: {message}");
                            if (stampFail is not null)
                            {
                                return stampFail.Value;
                            }

                            continue;
                        }

                        SessionStatus stamped = new("jobs.shell.stamp", message);
                        env.ReportStatus(stamped);
                        continue;
                    }

                case ProvisionJobKind.Wsl:
                    {
                        if (string.IsNullOrWhiteSpace(job.PackageId))
                        {
                            return FailJob(
                                env,
                                "jobs.failed",
                                $"Job '{job.Id}' kind wsl requires packageId (distro name).");
                        }

                        if (job.WslInstallKind is WslInstallKind.FromFile)
                        {
                            JobsRunResult? fromFile = await RunWslFromFileInstallAsync(env, job, ct)
                                .ConfigureAwait(false);
                            if (fromFile is not null)
                            {
                                return fromFile.Value;
                            }

                            if (job.NeedsReboot)
                            {
                                return context.RequestReboot();
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
                        JobsRunResult? platform = await RunWslPlatformJobAsync(context, ct)
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
                JobsRunResult? spawnFail = context.RecordPackageFailure(
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
                    return context.RequestReboot();
                }

                JobsRunResult? runFail = context.RecordPackageFailure(
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
                return context.RequestReboot();
            }
        }

        WritePackagesEvidence(env.Evidence, packageFailures);

        string okMessage = packageFailures.Count > 0
            ? $"Provisioning jobs completed with {packageFailures.Count} package failure(s)."
            : "Provisioning jobs completed.";
        SessionStatus ok = new("jobs.ok", okMessage);
        env.ReportStatus(ok);
        return new JobsRunResult(JobsRunKind.Completed, ok);
    }

    /// <summary>Paint the failure, log the phase, and end the jobs phase — the only way a job fails.</summary>
    private static JobsRunResult FailJob(
        JobRunnerEnv env,
        string code,
        string message)
    {
        SessionStatus status = new(code, message);
        env.ReportStatus(status);
        return new JobsRunResult(JobsRunKind.Failed, status);
    }

    private sealed class JobContext(
        JobRunnerEnv env,
        List<PackageFailureEntry> packageFailures,
        ProvisionJob job,
        int index)
    {
        public JobRunnerEnv Env { get; } = env;

        public ProvisionJob Job { get; } = job;

        public JobsRunResult? RecordPackageFailure(
            string code,
            string message,
            int exitCode = 1)
        {
            if (!IsPackageKind(Job.Kind) || Env.PackageStrict)
            {
                return FailJob(Env, code, message);
            }

            packageFailures.Add(
                new PackageFailureEntry(Job.Id, Job.Kind.ToWire(), exitCode, message));
            return null;
        }

        public JobsRunResult RequestReboot()
        {
            int nextJobIndex = index + 1;
            SessionStatus reboot = new(
                "jobs.reboot",
                $"Job '{Job.Id}' requires reboot; checkpoint jobs:{nextJobIndex}.");
            return new JobsRunResult(JobsRunKind.NeedsReboot, reboot, nextJobIndex);
        }
    }

    private static bool IsPackageKind(ProvisionJobKind kind) => kind is
        ProvisionJobKind.Winget
        or ProvisionJobKind.WingetImport
        or ProvisionJobKind.Scoop
        or ProvisionJobKind.ScoopBatch
        or ProvisionJobKind.ShellStamp;

    private static void WritePackagesEvidence(
        IEvidenceSink evidence,
        List<PackageFailureEntry> failures)
    {
        if (failures.Count == 0)
        {
            return;
        }

        _ = evidence.Write(
            new PackagesEvidenceFile(ProvisioningSession.PackagesEvidenceSchemaVersion, failures));
    }
}

