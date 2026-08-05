namespace WinMint.Provisioning;

using System.Net.Http.Json;
using System.Reflection.PortableExecutable;
using System.Text.Json;
using System.Text.Json.Serialization;

public static class ProvisioningSession
{
    public const string ForbiddenAutologonUser = "defaultuser0";
    public const string EvidenceSchemaVersion = "winmint.provisioning.evidence/v1";
    public const string ExplorerShell = "explorer.exe";

    /// <summary>App Installer / winget package family (Microsoft-documented FirstLogon register target).</summary>
    public const string DesktopAppInstallerFamilyName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe";

    public static SessionResult Run(
        SessionMode mode,
        ProvisioningBundle bundle,
        SessionEnvironment env,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(bundle);
        ArgumentNullException.ThrowIfNull(env);

        return mode switch
        {
            SessionMode.MachineSetup => RunMachineSetup(bundle, env, ct),
            SessionMode.Shell => RunShell(bundle, env, ct),
            _ => new SessionResult(
                SessionOutcome.Failed,
                new SessionStatus("session.mode.unknown", $"Unknown mode: {mode}"),
                []),
        };
    }

    private static SessionResult RunShell(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        CancellationToken ct)
    {
        List<string> phases = [];
        List<EvidenceSnapshot> emitted = [];
        // Tenure deadlines are monotonic (survive Hyper-V IC/NTP UTC jumps); wall clock for evidence only.
        long tenureStartTs = env.Time.GetTimestamp();
        DateTimeOffset shellStartUtc = env.Time.GetUtcNow();
        long? firstPaintMs = null;

        if (ct.IsCancellationRequested)
        {
            return FailOpen(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.cancelled", "Shell tenure cancelled."),
                dwell: false,
                firstPaintMs);
        }

        if (env.Evidence is null)
        {
            return FailOpen(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.evidence.required", "Shell tenure requires a write-only evidence sink."),
                dwell: false,
                firstPaintMs);
        }

        // Bootstrap: in-progress checkpoint + missing/stale heartbeat ⇒ fail-open.
        TenureState tenure = env.Checkpoints.ReadTenure();
        CheckpointState? storedCheckpoint = env.Checkpoints.TryReadCheckpoint();
        if (tenure.CheckpointInProgress && IsStaleHeartbeat(bundle, env, tenure))
        {
            env.Checkpoints.ClearCheckpoint();
            return FailOpen(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.stale",
                    "In-progress checkpoint with missing or stale heartbeat; fail-open unlock."),
                dwell: false,
                firstPaintMs);
        }

        if (tenure.CheckpointInProgress && storedCheckpoint is null)
        {
            env.Checkpoints.ClearCheckpoint();
            return FailOpen(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.checkpoint.invalid",
                    "In-progress checkpoint missing or empty; fail-closed."),
                dwell: false,
                firstPaintMs);
        }

        CheckpointState? resume = storedCheckpoint ?? bundle.Resume;
        int jobStartIndex = 0;
        if (resume is not null
            && TryParseJobsPhase(resume.Phase, out int resumeJobIndex))
        {
            jobStartIndex = resumeJobIndex;
        }

        env.Checkpoints.WriteHeartbeat(env.Time.GetUtcNow());

        // FirstPaint — opaque frame before any settle work (S3 order; S4 measures latency).
        env.Splash.Show();
        firstPaintMs = (long)(env.Time.GetUtcNow() - shellStartUtc).TotalMilliseconds;
        SessionStatus paintStatus = new("shell.first_paint", "First opaque splash frame.");
        env.Splash.SetStatus(paintStatus);
        phases.Add(paintStatus.Code);

        if (jobStartIndex > 0 && resume is not null)
        {
            SessionStatus resumed = new("checkpoint.resume", $"Resuming from {resume.Phase}.");
            env.Splash.SetStatus(resumed);
            phases.Add(resumed.Code);

            // Settle already ran before NeedsReboot. Skip re-settle on resume (idempotent restore;
            // also avoids re-entering TZ/location churn right after OS reboot).
            SessionStatus settleSkip = new(
                "settle.resume_skip",
                "DMA settle skipped on checkpoint resume.");
            env.Splash.SetStatus(settleSkip);
            phases.Add(settleSkip.Code);
        }
        else
        {
            if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
            {
                return FailOpen(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs);
            }

            SettlePhaseResult settle = RunSettle(bundle, env, phases, tenureStartTs, ct);
            if (settle.TimedOut)
            {
                return FailOpen(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs);
            }

            if (settle.HardFailed)
            {
                return FailOpen(bundle, env, phases, emitted, settle.Status, dwell: true, firstPaintMs);
            }
        }

        if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
        {
            return FailOpen(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs);
        }

        JobsPhaseResult jobs;
        try
        {
            jobs = RunJobs(bundle, env, phases, tenureStartTs, jobStartIndex, ct);
        }
        catch (OperationCanceledException)
        {
            return FailOpen(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.cancelled", "Shell tenure cancelled."),
                dwell: false,
                firstPaintMs);
        }

        if (jobs.TimedOut)
        {
            return FailOpen(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs);
        }

        if (jobs.Outcome == SessionOutcome.Failed)
        {
            return FailOpen(bundle, env, phases, emitted, jobs.Status, dwell: true, firstPaintMs);
        }

        if (jobs.Outcome == SessionOutcome.Reboot)
        {
            // Keep Supervisor as Shell — do not unlock.
            EvidenceSnapshot rebootSnap = env.Evidence.Write(
                new ProvisioningEvidenceDocument(
                    SchemaVersion: EvidenceSchemaVersion,
                    Outcome: SessionOutcome.Reboot.ToString(),
                    StatusCode: jobs.Status.Code,
                    StatusMessage: jobs.Status.Message,
                    Phases: phases,
                    FirstPaintMs: firstPaintMs));
            emitted.Add(rebootSnap);
            env.Reboot?.RequestReboot();
            return new SessionResult(SessionOutcome.Reboot, jobs.Status, emitted);
        }

        // Finishing: unlock → Complete. (No AppearanceOnce until Profile appearance grilled.)
        env.Checkpoints.ClearCheckpoint();

        // Unlock before Complete evidence so S4 never claims green while Shell is still Supervisor.
        if (!TryUnlock(env) || !IsExplorerShell(env.Winlogon.GetShell()))
        {
            return FailOpen(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.unlock_failed",
                    "Winlogon Shell was not restored to explorer.exe after jobs."),
                dwell: true,
                firstPaintMs);
        }

        EvidenceSnapshot snap = env.Evidence.Write(
            new ProvisioningEvidenceDocument(
                SchemaVersion: EvidenceSchemaVersion,
                Outcome: SessionOutcome.Complete.ToString(),
                StatusCode: jobs.Status.Code,
                StatusMessage: jobs.Status.Message,
                Phases: phases,
                FirstPaintMs: firstPaintMs));
        emitted.Add(snap);

        TryEraseResidue(env);

        return new SessionResult(SessionOutcome.Complete, jobs.Status, emitted);
    }

    private static void TryEraseResidue(SessionEnvironment env)
    {
        if (env.ResidueCleaner is null)
        {
            return;
        }

        try
        {
            env.ResidueCleaner.TryEraseAfterComplete();
        }
        catch (Exception)
        {
            // ponytail: Explorer already held; residue erase is best-effort (ADR-008)
        }
    }

    private static bool IsExplorerShell(string? shell) =>
        !string.IsNullOrWhiteSpace(shell)
        && shell.Trim().Equals(ExplorerShell, StringComparison.OrdinalIgnoreCase);

    private static bool IsStaleHeartbeat(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        TenureState tenure)
    {
        if (tenure.HeartbeatUtc is null)
        {
            return true;
        }

        return env.Time.GetUtcNow() - tenure.HeartbeatUtc.Value > bundle.Policy.StaleTenureThreshold;
    }

    private static bool IsTimedOut(SessionEnvironment env, long startTimestamp, TimeSpan timeout) =>
        env.Time.GetElapsedTime(startTimestamp) >= timeout;

    private static SessionStatus TimeoutStatus() =>
        new("shell.timeout", "Shell tenure timeout.");

    private static void Unlock(IWinlogonRegistry winlogon) =>
        winlogon.SetShell(ExplorerShell);

    private static SessionResult FailOpen(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        List<string> phases,
        List<EvidenceSnapshot> emitted,
        SessionStatus status,
        bool dwell,
        long? firstPaintMs)
    {
        env.Splash.SetStatus(status);
        if (!phases.Contains(status.Code))
        {
            phases.Add(status.Code);
        }

        if (dwell && bundle.Policy.FailedDwell > TimeSpan.Zero)
        {
            try
            {
                Task.Delay(bundle.Policy.FailedDwell, env.Time, CancellationToken.None)
                    .GetAwaiter()
                    .GetResult();
            }
            catch (OperationCanceledException)
            {
                // ponytail: dwell best-effort before fail-open unlock
            }
        }

        env.Checkpoints.ClearCheckpoint();

        if (env.Evidence is not null)
        {
            EvidenceSnapshot snap = env.Evidence.Write(
                new ProvisioningEvidenceDocument(
                    SchemaVersion: EvidenceSchemaVersion,
                    Outcome: SessionOutcome.Failed.ToString(),
                    StatusCode: status.Code,
                    StatusMessage: status.Message,
                    Phases: phases,
                    FirstPaintMs: firstPaintMs));
            emitted.Add(snap);
        }

        // Unlock after evidence — custom Shell is medium-IL and may lack HKLM write.
        _ = TryUnlock(env);

        return new SessionResult(SessionOutcome.Failed, status, emitted);
    }

    /// <returns>true when SetShell(explorer) did not throw.</returns>
    private static bool TryUnlock(SessionEnvironment env)
    {
        try
        {
            Unlock(env.Winlogon);
            return true;
        }
        catch (Exception)
        {
            // ponytail: evidence already durable; MachineSetup grants unlock ACL for Shell (see GrantShellUnlockAccess)
            return false;
        }
    }

    private readonly record struct JobsPhaseResult(
        SessionOutcome Outcome,
        SessionStatus Status,
        bool TimedOut);

    private static bool TryParseJobsPhase(string phase, out int jobIndex)
    {
        jobIndex = 0;
        const string prefix = "jobs:";
        if (!phase.StartsWith(prefix, StringComparison.Ordinal)
            || !int.TryParse(phase.AsSpan(prefix.Length), out jobIndex)
            || jobIndex < 0)
        {
            return false;
        }

        return true;
    }

    private static JobsPhaseResult RunJobs(
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
            else if (string.Equals(job.Kind, "winget", StringComparison.OrdinalIgnoreCase))
            {
                if (string.IsNullOrWhiteSpace(job.PackageId))
                {
                    return FailJob("jobs.failed", $"Job '{job.Id}' kind winget requires packageId.");
                }

                // FirstLogon: App Installer is often provisioned but not yet registered for the
                // interactive user — winget.exe missing until RegisterByFamilyName (MS docs).
                // Framework ACLs are MachineSetup-only (SYSTEM); Shell must not re-call takeown/icacls.
                // Path seam: AppX only — no LocalAppData alias / PATH "winget" fallback (deepening #51).
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
                    return FailJob(
                        "jobs.winget.register_failed",
                        $"{job.Id}: register {DesktopAppInstallerFamilyName}: {ex.Message}");
                }

                string? resolvedWinget = env.Appx.TryResolveWingetExecutablePath();
                if (string.IsNullOrWhiteSpace(resolvedWinget))
                {
                    return FailJob(
                        "jobs.winget.path_missing",
                        $"{job.Id}: winget.exe not found after registering {DesktopAppInstallerFamilyName}.");
                }

                fileName = resolvedWinget;

                arguments =
                [
                    "install",
                    "--id",
                    job.PackageId,
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
            else if (string.Equals(job.Kind, "scoop", StringComparison.OrdinalIgnoreCase))
            {
                if (string.IsNullOrWhiteSpace(job.PackageId))
                {
                    return FailJob("jobs.failed", $"Job '{job.Id}' kind scoop requires packageId.");
                }

                if (env.ResolveScoopCmd is null)
                {
                    return FailJob("jobs.failed", $"Job '{job.Id}' requires ResolveScoopCmd.");
                }

                string? scoopCmd = env.ResolveScoopCmd();
                if (scoopCmd is null)
                {
                    ProcessStartResult bootstrap;
                    try
                    {
                        // Official admin bootstrap — ScoopInstaller/Install (see PROVISIONINGSESSION).
                        // Inbox powershell.exe only; not guest pwsh product control plane.
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
                        return FailJob(
                            "jobs.scoop.bootstrap_failed",
                            $"{job.Id}: scoop bootstrap spawn: {ex.Message}");
                    }

                    if (bootstrap.ExitCode != 0)
                    {
                        return FailJob(
                            "jobs.scoop.bootstrap_failed",
                            $"{job.Id}: scoop bootstrap exited {bootstrap.ExitCode} (network required).");
                    }

                    scoopCmd = env.ResolveScoopCmd();
                    if (scoopCmd is null)
                    {
                        return FailJob(
                            "jobs.scoop.bootstrap_failed",
                            $"{job.Id}: scoop.cmd missing after bootstrap.");
                    }
                }

                fileName = scoopCmd;
                arguments = ["install", job.PackageId];
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
                return FailJob("jobs.spawn_failed", $"{job.Id}: {ex.Message}");
            }

            if (started.ExitCode != 0)
            {
                return FailJob("jobs.failed", $"Job '{job.Id}' exited {started.ExitCode}.");
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

        SessionStatus ok = new("jobs.ok", "Provisioning jobs completed.");
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
        if (string.IsNullOrWhiteSpace(job.PackageId)
            || !TryResolveDohProvider(job.PackageId, out string primary, out string secondary, out string template))
        {
            SessionStatus bad = new(
                "jobs.failed",
                $"Job '{job.Id}' kind doh.set requires packageId cloudflare|google|quad9.");
            env.Splash.SetStatus(bad);
            phases.Add(bad.Code);
            return new JobsPhaseResult(SessionOutcome.Failed, bad, TimedOut: false);
        }

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

    private static bool TryResolveDohProvider(
        string id,
        out string primary,
        out string secondary,
        out string template)
    {
        switch (id.Trim().ToLowerInvariant())
        {
            case "cloudflare":
                primary = "1.1.1.1";
                secondary = "1.0.0.1";
                template = "https://cloudflare-dns.com/dns-query";
                return true;
            case "google":
                primary = "8.8.8.8";
                secondary = "8.8.4.4";
                template = "https://dns.google/dns-query";
                return true;
            case "quad9":
                primary = "9.9.9.9";
                secondary = "149.112.112.112";
                template = "https://dns.quad9.net/dns-query";
                return true;
            default:
                primary = secondary = template = "";
                return false;
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

    private readonly record struct SettlePhaseResult(bool HardFailed, bool TimedOut, SessionStatus Status);

    /// <summary>
    /// Bounded restore + poll; only the final snapshot gates hard locale / GeoID / TZ.
    /// Soft location-services mismatch warns and continues.
    /// </summary>
    private static SettlePhaseResult RunSettle(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        List<string> phases,
        long tenureStartTs,
        CancellationToken ct)
    {
        SessionStatus begin = new("settle.begin", "DMA settle start.");
        env.Splash.SetStatus(begin);
        phases.Add(begin.Code);

        if (!bundle.Dma.Enabled)
        {
            SessionStatus skipped = new("settle.skipped", "DMA disabled; settle skipped.");
            env.Splash.SetStatus(skipped);
            phases.Add(skipped.Code);
            return new SettlePhaseResult(HardFailed: false, TimedOut: false, skipped);
        }

        if (string.IsNullOrWhiteSpace(bundle.Dma.Locale)
            || bundle.Dma.GeoId is null
            || string.IsNullOrWhiteSpace(bundle.Dma.TimeZoneId))
        {
            SessionStatus incomplete = new(
                "settle.target_incomplete",
                "DMA settle requires locale, geoId, and timeZoneId.");
            env.Splash.SetStatus(incomplete);
            phases.Add(incomplete.Code);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, incomplete);
        }

        try
        {
            env.Region.Apply(bundle.Dma);
        }
        catch (Exception ex)
        {
            SessionStatus applyFailed = new("settle.apply_failed", ex.Message);
            env.Splash.SetStatus(applyFailed);
            phases.Add(applyFailed.Code);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, applyFailed);
        }

        long settleStartTs = env.Time.GetTimestamp();
        TimeSpan settleBudget = bundle.Policy.SettleDeadline;

        while (true)
        {
            if (ct.IsCancellationRequested)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                env.Splash.SetStatus(cancelled);
                phases.Add(cancelled.Code);
                return new SettlePhaseResult(HardFailed: true, TimedOut: false, cancelled);
            }

            if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
            {
                return new SettlePhaseResult(HardFailed: true, TimedOut: true, TimeoutStatus());
            }

            try
            {
                RegionState snap = env.Region.Read();
                if (HardFieldsMatch(snap, bundle.Dma))
                {
                    // Still take an authoritative final snapshot after the loop.
                    break;
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // ponytail: intermediate DMA probe fail-open — final snapshot after loop is authoritative
                _ = ex;
            }

            TimeSpan settleElapsed = env.Time.GetElapsedTime(settleStartTs);
            TimeSpan tenureElapsed = env.Time.GetElapsedTime(tenureStartTs);
            if (settleElapsed >= settleBudget
                || tenureElapsed >= bundle.Policy.WallClockTimeout)
            {
                break;
            }

            TimeSpan wait = bundle.Policy.SettlePollInterval;
            TimeSpan remainingSettle = settleBudget - settleElapsed;
            TimeSpan remainingTenure = bundle.Policy.WallClockTimeout - tenureElapsed;
            if (remainingSettle < wait)
            {
                wait = remainingSettle;
            }

            if (remainingTenure < wait)
            {
                wait = remainingTenure;
            }

            if (wait <= TimeSpan.Zero)
            {
                break;
            }

            try
            {
                // ponytail: sync settle loop — ConfigureAwait(false) while IAppx/session stay sync
                Task.Delay(wait, env.Time, ct).ConfigureAwait(false).GetAwaiter().GetResult();
            }
            catch (OperationCanceledException)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                env.Splash.SetStatus(cancelled);
                phases.Add(cancelled.Code);
                return new SettlePhaseResult(HardFailed: true, TimedOut: false, cancelled);
            }
        }

        if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
        {
            return new SettlePhaseResult(HardFailed: true, TimedOut: true, TimeoutStatus());
        }

        // Final snapshot gates hard fields — always read once after the bounded poll.
        RegionState final;
        try
        {
            final = env.Region.Read();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            SessionStatus readFailed = new("settle.read_failed", ex.Message);
            env.Splash.SetStatus(readFailed);
            phases.Add(readFailed.Code);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, readFailed);
        }

        if (!HardFieldsMatch(final, bundle.Dma))
        {
            SessionStatus mismatch = new(
                "settle.hard_mismatch",
                $"Final snapshot hard fields mismatch (locale={final.Locale}, geoId={final.GeoId}, tz={final.TimeZoneId}).");
            env.Splash.SetStatus(mismatch);
            phases.Add(mismatch.Code);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, mismatch);
        }

        if (bundle.Dma.LocationServicesEnabled is bool expectedLocation
            && final.LocationServicesEnabled != expectedLocation)
        {
            SessionStatus warn = new(
                "settle.location_warn",
                $"Location-services posture is {final.LocationServicesEnabled}; expected {expectedLocation}.");
            env.Splash.SetStatus(warn);
            phases.Add(warn.Code);
            return new SettlePhaseResult(HardFailed: false, TimedOut: false, warn);
        }

        SessionStatus ok = new("settle.ok", "DMA hard fields settled.");
        env.Splash.SetStatus(ok);
        phases.Add(ok.Code);
        return new SettlePhaseResult(HardFailed: false, TimedOut: false, ok);
    }

    private static bool HardFieldsMatch(RegionState actual, DmaSettleTarget target) =>
        string.Equals(actual.Locale, target.Locale, StringComparison.OrdinalIgnoreCase)
        && actual.GeoId == target.GeoId
        && string.Equals(actual.TimeZoneId, target.TimeZoneId, StringComparison.OrdinalIgnoreCase);

    private static SessionResult RunMachineSetup(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        CancellationToken ct)
    {
        if (ct.IsCancellationRequested)
        {
            return Fail("machineSetup.cancelled", "Machine setup cancelled.");
        }

        string username = bundle.Account.Username.Trim();
        string password = bundle.Account.Password;
        if (string.IsNullOrWhiteSpace(username))
        {
            return Fail("machineSetup.account.empty", "Account username is required.");
        }

        if (string.Equals(username, ForbiddenAutologonUser, StringComparison.OrdinalIgnoreCase))
        {
            return Fail(
                "machineSetup.account.forbidden",
                $"Refusing AutoAdminLogon for forbidden user '{ForbiddenAutologonUser}'.");
        }

        try
        {
            env.Winlogon.SetAutoLogon(username, password);
            env.Winlogon.GrantShellUnlockAccess(username);
            if (env.Winlogon.GetAutoAdminLogon()
                && string.Equals(
                    env.Winlogon.GetDefaultUserName()?.Trim(),
                    ForbiddenAutologonUser,
                    StringComparison.OrdinalIgnoreCase))
            {
                return Fail(
                    "machineSetup.account.forbidden",
                    $"Refusing to leave '{ForbiddenAutologonUser}' with AutoAdminLogon enabled.");
            }
        }
        catch (Exception ex)
        {
            return Fail("machineSetup.autologon.stamp_failed", ex.Message);
        }

        // No further use of stamp password in this phase (disk wipe next; string GC lifetime remains).
        password = "";
        ProvisioningBundle scrubbedView = bundle with
        {
            Account = new AccountStamp(username, ""),
        };

        string expectedShell = scrubbedView.Supervisor.ShellPath;
        SessionResult? shellFailure = null;
        try
        {
            string? shell = env.Winlogon.GetShell();
            if (!ShellEquals(shell, expectedShell))
            {
                env.Winlogon.SetShell(expectedShell);
                shell = env.Winlogon.GetShell();
            }

            if (!ShellEquals(shell, expectedShell))
            {
                shellFailure = Fail(
                    "machineSetup.shell.verify_failed",
                    $"Winlogon Shell is '{shell ?? "<null>"}' after restamp; expected '{expectedShell}'.");
            }
        }
        catch (Exception ex)
        {
            shellFailure = Fail("machineSetup.shell.verify_failed", ex.Message);
        }

        if (env.WipeSecrets is not null)
        {
            try
            {
                env.WipeSecrets(scrubbedView);
            }
            catch (Exception ex)
            {
                return Fail("machineSetup.secret_wipe_failed", ex.Message);
            }
        }

        if (shellFailure is not null)
        {
            return shellFailure;
        }

        // SetupComplete runs as SYSTEM — only elevated window before FirstLogon medium-IL Shell.
        // ponytail: best-effort; winget register still fails closed if ACLs stay wrong.
        if (env.Appx is not null)
        {
            try
            {
                env.Appx.EnsureSystemFullControlOnWingetFrameworkPackages();
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // ponytail: MachineSetup fail-open on winget ACL prep — Shell register still fail-closed
                _ = ex;
            }
        }

        // OOBE often leaves defaultuser0 Enabled on the lock-screen picker; Unattend cannot prevent it.
        // ponytail: best-effort delete (+ Win32 adapter may schedule ONLOGON retry if SetupComplete raced OOBE).
        if (env.LocalAccounts is not null)
        {
            try
            {
                env.LocalAccounts.TryDeleteLocalUserAndProfile(ForbiddenAutologonUser);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // swallow — leftover temp user must not fail MachineSetup
            }
        }

        return new SessionResult(
            SessionOutcome.Complete,
            new SessionStatus("machineSetup.ok", "Autologon stamped; Shell verified; secrets wiped."),
            []);
    }

    private static bool ShellEquals(string? actual, string expected) =>
        !string.IsNullOrWhiteSpace(actual)
        && string.Equals(actual.Trim(), expected.Trim(), StringComparison.OrdinalIgnoreCase);

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

    private static SessionResult Fail(string code, string message) =>
        new(SessionOutcome.Failed, new SessionStatus(code, message), []);
}

internal sealed record GitHubRelease(
    [property: JsonPropertyName("assets")] GitHubAsset[]? Assets);

internal sealed record GitHubAsset(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("browser_download_url")] string? BrowserDownloadUrl);

[JsonSerializable(typeof(GitHubRelease))]
internal sealed partial class GitHubReleaseJsonContext : JsonSerializerContext;

internal sealed record NativePackageAuditDocument(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("packages")] IReadOnlyList<NativePackageAuditEntry> Packages);

internal sealed record NativePackageAuditEntry(
    [property: JsonPropertyName("wingetId")] string WingetId,
    [property: JsonPropertyName("binaryPath")] string? BinaryPath,
    [property: JsonPropertyName("isArm64Native")] bool? IsArm64Native);

[JsonSerializable(typeof(NativePackageAuditDocument))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class NativePackageAuditJsonContext : JsonSerializerContext;
