using System.Security;
using System.Text.Json.Serialization;

using WinMint.Contracts;

namespace WinMint.Provisioning;

public static partial class ProvisioningSession
{
    public const string ForbiddenAutologonUser = "defaultuser0";
    public const string EvidenceSchemaVersion = "winmint.provisioning.evidence/v1";
    public const string PackagesEvidenceSchemaVersion = "winmint.packages.evidence/v1";
    public const string ExplorerShell = "explorer.exe";

    /// <summary>App Installer / winget package family (Microsoft-documented FirstLogon register target).</summary>
    public const string DesktopAppInstallerFamilyName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe";

    /// <summary>Run the FirstLogon Shell tenure for a provisioning bundle against the live guest.</summary>
    public static async Task<SessionResult> RunShellAsync(
        ProvisioningBundle bundle,
        ShellEnvironment env,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(bundle);
        ArgumentNullException.ThrowIfNull(env);

        List<string> phases = [];
        List<EvidenceSnapshot> emitted = [];
        // Tenure deadlines are monotonic (survive Hyper-V IC/NTP UTC jumps); wall clock for evidence only.
        long tenureStartTs = env.Time.GetTimestamp();
        DateTimeOffset shellStartUtc = env.Time.GetUtcNow();
        long? firstPaintMs = null;

        if (ct.IsCancellationRequested)
        {
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.cancelled", "Shell tenure cancelled."),
                dwell: false,
                firstPaintMs).ConfigureAwait(false);
        }

        // Bootstrap: in-progress checkpoint + missing/stale heartbeat ⇒ fail-open.
        TenureState tenure = env.Guest.Checkpoints.ReadTenure();
        CheckpointState? storedCheckpoint = env.Guest.Checkpoints.TryReadCheckpoint();
        if (tenure.CheckpointInProgress && IsStaleHeartbeat(bundle, env, tenure))
        {
            env.Guest.Checkpoints.ClearCheckpoint();
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.stale",
                    "In-progress checkpoint with missing or stale heartbeat; fail-open unlock."),
                dwell: false,
                firstPaintMs).ConfigureAwait(false);
        }

        if (tenure.CheckpointInProgress && storedCheckpoint is null)
        {
            env.Guest.Checkpoints.ClearCheckpoint();
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.checkpoint.invalid",
                    "In-progress checkpoint missing or empty; fail-closed."),
                dwell: false,
                firstPaintMs).ConfigureAwait(false);
        }

        CheckpointState? resume = storedCheckpoint ?? bundle.Resume;
        int jobStartIndex = 0;
        if (resume is not null
            && TryParseJobsPhase(resume.Phase, out int resumeJobIndex))
        {
            jobStartIndex = resumeJobIndex;
        }

        env.Guest.Checkpoints.WriteHeartbeat(env.Time.GetUtcNow());

        // FirstPaint — opaque frame before any settle work (S3 order; S4 measures latency).
        env.Splash.Show();
        firstPaintMs = (long)(env.Time.GetUtcNow() - shellStartUtc).TotalMilliseconds;
        SessionStatus paintStatus = new("shell.firstPaint", "First opaque splash frame.");
        Note(env, phases, paintStatus);

        if (jobStartIndex > 0 && resume is not null)
        {
            SessionStatus resumed = new("checkpoint.resume", $"Resuming from {resume.Phase}.");
            Note(env, phases, resumed);

            // Settle already ran before NeedsReboot. Skip re-settle on resume (idempotent restore;
            // also avoids re-entering TZ/location churn right after OS reboot).
            SessionStatus settleSkip = new(
                "settle.resumeSkip",
                "DMA settle skipped on checkpoint resume.");
            Note(env, phases, settleSkip);

            // Sticky setup region is cheap and must survive reboot even when visible settle is skipped.
            SettlePhaseResult? setupOnResume = EnsureDmaSetupRegionForSettle(bundle, env, phases);
            if (setupOnResume is { HardFailed: true })
            {
                return await FailOpenAsync(
                        bundle,
                        env,
                        phases,
                        emitted,
                        setupOnResume.Value.Status,
                        dwell: true,
                        firstPaintMs)
                    .ConfigureAwait(false);
            }
        }
        else
        {
            if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
            {
                return await FailOpenAsync(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs)
                    .ConfigureAwait(false);
            }

            SettlePhaseResult settle = await RunSettleAsync(bundle, env, phases, tenureStartTs, ct)
                .ConfigureAwait(false);
            if (settle.TimedOut)
            {
                return await FailOpenAsync(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs)
                    .ConfigureAwait(false);
            }

            if (settle.HardFailed)
            {
                return await FailOpenAsync(bundle, env, phases, emitted, settle.Status, dwell: true, firstPaintMs)
                    .ConfigureAwait(false);
            }
        }

        if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
        {
            return await FailOpenAsync(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs)
                .ConfigureAwait(false);
        }

        if (bundle.RequiresNetwork)
        {
            SessionStatus? network = await EnsureNetworkAvailableAsync(env, phases, ct)
                .ConfigureAwait(false);
            if (network is not null)
            {
                return await FailOpenAsync(
                        bundle,
                        env,
                        phases,
                        emitted,
                        network.Value,
                        dwell: true,
                        firstPaintMs)
                    .ConfigureAwait(false);
            }
        }

        JobsRunResult jobs;
        try
        {
            JobRunnerEnv runnerEnv = new(
                RemoveProvisionedAppx: bundle.RemoveProvisionedAppx ?? [],
                Processes: env.Guest.Processes,
                Time: env.Time,
                ReportStatus: status => Note(env, phases, status),
                Evidence: env.Evidence,
                PackageStrict: bundle.PackageStrict,
                WallClockTimeout: bundle.Policy.WallClockTimeout,
                TenureStartTimestamp: tenureStartTs,
                StartIndex: jobStartIndex,
                Appx: env.Guest.Appx,
                ResolveScoopCmd: env.Guest.ResolveScoopCmd,
                AssetDownload: env.Guest.AssetDownload,
                IsWslPlatformReady: env.Guest.IsWslPlatformReady,
                ApplyWorkstationQuiet: env.Guest.ApplyWorkstationQuiet,
                SuppressWslOobe: env.Guest.SuppressWslOobe);
            jobs = await ProvisioningJobRunner.Run(bundle.Jobs, runnerEnv, ct)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.cancelled", "Shell tenure cancelled."),
                dwell: false,
                firstPaintMs).ConfigureAwait(false);
        }

        if (jobs.Kind == JobsRunKind.TimedOut)
        {
            return await FailOpenAsync(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs)
                .ConfigureAwait(false);
        }

        if (jobs.Kind == JobsRunKind.Failed)
        {
            return await FailOpenAsync(bundle, env, phases, emitted, jobs.Status, dwell: true, firstPaintMs)
                .ConfigureAwait(false);
        }

        if (jobs.Kind == JobsRunKind.NeedsReboot)
        {
            if (jobs.NextJobIndex is not int nextJobIndex)
            {
                return await FailOpenAsync(
                        bundle,
                        env,
                        phases,
                        emitted,
                        new SessionStatus("jobs.checkpoint.invalid", "Job runner omitted the reboot checkpoint index."),
                        dwell: true,
                        firstPaintMs)
                    .ConfigureAwait(false);
            }

            // Keep Supervisor as Shell — do not unlock.
            env.Guest.Checkpoints.WriteCheckpoint(new CheckpointState($"jobs:{nextJobIndex}"));
            env.Guest.Checkpoints.WriteHeartbeat(env.Time.GetUtcNow());
            Note(env, phases, jobs.Status);
            EvidenceSnapshot rebootSnap = env.Evidence.Write(
                new ProvisioningEvidenceFile(
                    SchemaVersion: EvidenceSchemaVersion,
                    Outcome: SessionOutcome.Reboot.ToString(),
                    StatusCode: jobs.Status.Code,
                    StatusMessage: jobs.Status.Message,
                    Phases: phases,
                    FirstPaintMs: firstPaintMs));
            emitted.Add(rebootSnap);
            env.Guest.Reboot?.RequestReboot();
            return new SessionResult(SessionOutcome.Reboot, jobs.Status, emitted);
        }

        // Finishing: unlock → Complete. (No AppearanceOnce until Profile appearance grilled.)
        env.Guest.Checkpoints.ClearCheckpoint();

        // Unlock before Complete evidence so S4 never claims green while Shell is still Supervisor.
        if (!TryUnlock(env) || !IsExplorerShell(env.Guest.Winlogon.GetShell()))
        {
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.unlockFailed",
                    "Winlogon Shell was not restored to explorer.exe after jobs."),
                dwell: true,
                firstPaintMs).ConfigureAwait(false);
        }

        EvidenceSnapshot snap = env.Evidence.Write(
            new ProvisioningEvidenceFile(
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

    /// <summary>
    /// Paint a status and append it to the ordered phase log. Every phase the session emits crosses
    /// here, so the log the evidence document carries is the log the splash showed.
    /// </summary>
    private static void Note(ShellEnvironment env, List<string> phases, SessionStatus status)
    {
        env.Splash.SetStatus(status);
        phases.Add(status.Code);
    }

    private static void TryEraseResidue(ShellEnvironment env)
    {
        if (env.Guest.ResidueCleaner is null)
        {
            return;
        }

        try
        {
            env.Guest.ResidueCleaner.TryEraseAfterComplete();
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
        ShellEnvironment env,
        TenureState tenure)
    {
        if (tenure.HeartbeatUtc is null)
        {
            return true;
        }

        return env.Time.GetUtcNow() - tenure.HeartbeatUtc.Value > bundle.Policy.StaleTenureThreshold;
    }

    private static bool IsTimedOut(ShellEnvironment env, long startTimestamp, TimeSpan timeout) =>
        env.Time.GetElapsedTime(startTimestamp) >= timeout;

    private static SessionStatus TimeoutStatus() =>
        new("shell.timeout", "Shell tenure timeout.");

    private static void Unlock(IWinlogonRegistry winlogon) =>
        winlogon.SetShell(ExplorerShell);

    private static async Task<SessionResult> FailOpenAsync(
        ProvisioningBundle bundle,
        ShellEnvironment env,
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
                await Task.Delay(bundle.Policy.FailedDwell, env.Time, CancellationToken.None)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // ponytail: dwell best-effort before fail-open unlock
            }
        }

        env.Guest.Checkpoints.ClearCheckpoint();

        emitted.Add(env.Evidence.Write(
            new ProvisioningEvidenceFile(
                SchemaVersion: EvidenceSchemaVersion,
                Outcome: SessionOutcome.Failed.ToString(),
                StatusCode: status.Code,
                StatusMessage: status.Message,
                Phases: phases,
                FirstPaintMs: firstPaintMs)));

        // Unlock after evidence — custom Shell is medium-IL and may lack HKLM write.
        _ = TryUnlock(env);

        return new SessionResult(SessionOutcome.Failed, status, emitted);
    }

    /// <returns>true when SetShell(explorer) did not throw.</returns>
    private static bool TryUnlock(ShellEnvironment env)
    {
        try
        {
            Unlock(env.Guest.Winlogon);
            return true;
        }
        catch (Exception)
        {
            // ponytail: evidence already durable; MachineSetup grants unlock ACL for Shell (see GrantShellUnlockAccess)
            return false;
        }
    }

    private static async Task<SessionStatus?> EnsureNetworkAvailableAsync(
        ShellEnvironment env,
        List<string> phases,
        CancellationToken ct)
    {
        if (env.Guest.Connectivity is not null
            && await env.Guest.Connectivity.HasOutboundNetworkAsync(ct).ConfigureAwait(false))
        {
            SessionStatus ok = new("network.ok", "Outbound connectivity available.");
            Note(env, phases, ok);
            return null;
        }

        SessionStatus offline = new(
            "network.required.offline",
            "Plan requires network but outbound connectivity probe failed.");
        Note(env, phases, offline);
        return offline;
    }

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

    private readonly record struct SettlePhaseResult(bool HardFailed, bool TimedOut, SessionStatus Status);

    /// <summary>
    /// Bounded restore + poll; only the final snapshot gates hard locale / GeoID / TZ.
    /// Soft location-services mismatch warns and continues.
    /// </summary>
    private static async Task<SettlePhaseResult> RunSettleAsync(
        ProvisioningBundle bundle,
        ShellEnvironment env,
        List<string> phases,
        long tenureStartTs,
        CancellationToken ct)
    {
        SessionStatus begin = new("settle.begin", "DMA settle start.");
        Note(env, phases, begin);

        if (!bundle.DmaEnabled)
        {
            SessionStatus skipped = new("settle.skipped", "DMA disabled; settle skipped.");
            Note(env, phases, skipped);
            return new SettlePhaseResult(HardFailed: false, TimedOut: false, skipped);
        }

        // Same four fields Win32RegionSnapshot.Apply requires — a narrower gate here would
        // surface a missing target as settle.applyFailed instead of settle.targetIncomplete.
        if (string.IsNullOrWhiteSpace(bundle.Dma.Locale)
            || bundle.Dma.GeoId is null
            || string.IsNullOrWhiteSpace(bundle.Dma.TimeZoneId)
            || bundle.Dma.LocationServicesEnabled is null)
        {
            SessionStatus incomplete = new(
                "settle.targetIncomplete",
                "DMA settle requires locale, geoId, timeZoneId, and locationServicesEnabled.");
            Note(env, phases, incomplete);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, incomplete);
        }

        try
        {
            env.Guest.Region.Apply(bundle.Dma);
        }
        catch (Exception ex)
        {
            SessionStatus applyFailed = new("settle.applyFailed", ex.Message);
            Note(env, phases, applyFailed);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, applyFailed);
        }

        long settleStartTs = env.Time.GetTimestamp();
        TimeSpan settleBudget = bundle.Policy.SettleDeadline;

        while (true)
        {
            if (ct.IsCancellationRequested)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                Note(env, phases, cancelled);
                return new SettlePhaseResult(HardFailed: true, TimedOut: false, cancelled);
            }

            if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
            {
                return new SettlePhaseResult(HardFailed: true, TimedOut: true, TimeoutStatus());
            }

            try
            {
                RegionState snap = env.Guest.Region.Read();
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
                await Task.Delay(wait, env.Time, ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                Note(env, phases, cancelled);
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
            final = env.Guest.Region.Read();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            SessionStatus readFailed = new("settle.readFailed", ex.Message);
            Note(env, phases, readFailed);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, readFailed);
        }

        if (!HardFieldsMatch(final, bundle.Dma))
        {
            SessionStatus mismatch = new(
                "settle.hardMismatch",
                $"Final snapshot hard fields mismatch (locale={final.Locale}, geoId={final.GeoId}, tz={final.TimeZoneId}).");
            Note(env, phases, mismatch);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, mismatch);
        }

        SettlePhaseResult? setup = EnsureDmaSetupRegionForSettle(bundle, env, phases);
        if (setup is { HardFailed: true })
        {
            return setup.Value;
        }

        if (bundle.Dma.LocationServicesEnabled is bool expectedLocation
            && final.LocationServicesEnabled != expectedLocation)
        {
            SessionStatus warn = new(
                "settle.locationWarn",
                $"Location-services posture is {final.LocationServicesEnabled}; expected {expectedLocation}.");
            Note(env, phases, warn);
            return new SettlePhaseResult(HardFailed: false, TimedOut: false, warn);
        }

        SessionStatus ok = new("settle.ok", "DMA hard fields settled.");
        Note(env, phases, ok);
        return new SettlePhaseResult(HardFailed: false, TimedOut: false, ok);
    }

    private static SessionResult? EnsureDmaSetupRegionForMachineSetup(MachineSetupEnvironment env)
    {
        if (env.DmaSetup is null)
        {
            return Fail(
                "machineSetup.dmaSetupRegionFailed",
                "DmaSetup port required when DMA enabled.");
        }

        try
        {
            _ = env.DmaSetup.EnsureIreland();
            return null;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or SecurityException)
        {
            // ponytail: OOBE still holds DeviceRegion during SetupComplete. Exit 1 reseals to Recovery.
            // FirstLogon settle retries the latch; fail-closed stays for verify/null-port failures.
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Fail("machineSetup.dmaSetupRegionFailed", ex.Message);
        }
    }

    /// <summary>
    /// Repair-then-verify sticky DeviceRegion Ireland after visible settle (or on resume skip).
    /// </summary>
    private static SettlePhaseResult? EnsureDmaSetupRegionForSettle(
        ProvisioningBundle bundle,
        ShellEnvironment env,
        List<string> phases)
    {
        if (!bundle.DmaEnabled)
        {
            return null;
        }

        if (env.Guest.DmaSetup is null)
        {
            SessionStatus missing = new(
                "settle.deviceRegionFailed",
                "DmaSetup port required when DMA enabled.");
            Note(env, phases, missing);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, missing);
        }

        try
        {
            DmaSetupRegionEnsureResult result = env.Guest.DmaSetup.EnsureIreland();
            SessionStatus status = result == DmaSetupRegionEnsureResult.Repaired
                ? new("settle.deviceRegionRepaired", "DeviceRegion repaired to Ireland (68).")
                : new("settle.deviceRegionOk", "DeviceRegion already Ireland (68).");
            Note(env, phases, status);
            return new SettlePhaseResult(HardFailed: false, TimedOut: false, status);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            SessionStatus failed = new("settle.deviceRegionFailed", ex.Message);
            Note(env, phases, failed);
            return new SettlePhaseResult(HardFailed: true, TimedOut: false, failed);
        }
    }

    private static bool HardFieldsMatch(RegionState actual, DmaSettleTarget target) =>
        string.Equals(actual.Locale, target.Locale, StringComparison.OrdinalIgnoreCase)
        && actual.GeoId == target.GeoId
        && string.Equals(actual.TimeZoneId, target.TimeZoneId, StringComparison.OrdinalIgnoreCase);

    /// <summary>Run the SetupComplete/SYSTEM pass: stamp autologon, verify Shell, wipe secrets.</summary>
    public static Task<SessionResult> RunMachineSetupAsync(
        ProvisioningBundle bundle,
        MachineSetupEnvironment env,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(bundle);
        ArgumentNullException.ThrowIfNull(env);

        if (ct.IsCancellationRequested)
        {
            return Task.FromResult(Fail("machineSetup.cancelled", "Machine setup cancelled."));
        }

        string username = bundle.Account.Username.Trim();
        string password = bundle.Account.Password;
        if (string.IsNullOrWhiteSpace(username))
        {
            return Task.FromResult(Fail("machineSetup.account.empty", "Account username is required."));
        }

        if (string.Equals(username, ForbiddenAutologonUser, StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult(Fail(
                "machineSetup.account.forbidden",
                $"Refusing AutoAdminLogon for forbidden user '{ForbiddenAutologonUser}'."));
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
                return Task.FromResult(Fail(
                    "machineSetup.account.forbidden",
                    $"Refusing to leave '{ForbiddenAutologonUser}' with AutoAdminLogon enabled."));
            }
        }
        catch (Exception ex)
        {
            return Task.FromResult(Fail("machineSetup.autologon.stampFailed", ex.Message));
        }

        // No further use of stamp password in this phase (disk wipe next; string GC lifetime remains).
        password = "";
        ProvisioningBundle scrubbedView = bundle with
        {
            Account = new AccountStamp(username, ""),
        };

        string expectedShell = scrubbedView.SupervisorShellPath;
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
                    "machineSetup.shell.verifyFailed",
                    $"Winlogon Shell is '{shell ?? "<null>"}' after restamp; expected '{expectedShell}'.");
            }
        }
        catch (Exception ex)
        {
            shellFailure = Fail("machineSetup.shell.verifyFailed", ex.Message);
        }

        if (env.WipeSecrets is not null)
        {
            try
            {
                env.WipeSecrets(scrubbedView);
            }
            catch (Exception ex)
            {
                return Task.FromResult(Fail("machineSetup.secretWipeFailed", ex.Message));
            }
        }

        if (shellFailure is not null)
        {
            return Task.FromResult(shellFailure);
        }

        if (bundle.DmaEnabled)
        {
            SessionResult? dmaSetupFail = EnsureDmaSetupRegionForMachineSetup(env);
            if (dmaSetupFail is not null)
            {
                return Task.FromResult(dmaSetupFail);
            }
        }

        // SetupComplete runs as SYSTEM before FirstLogon medium-IL Shell (console hidden).
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

        return Task.FromResult(new SessionResult(
            SessionOutcome.Complete,
            new SessionStatus("machineSetup.ok", "Autologon stamped; Shell verified; secrets wiped."),
            []));
    }

    private static bool ShellEquals(string? actual, string expected) =>
        !string.IsNullOrWhiteSpace(actual)
        && string.Equals(actual.Trim(), expected.Trim(), StringComparison.OrdinalIgnoreCase);

    private static SessionResult Fail(string code, string message) =>
        new(SessionOutcome.Failed, new SessionStatus(code, message), []);
}

internal sealed record NativePackageAuditFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("packages")] IReadOnlyList<NativePackageAuditEntryFile> Packages);

internal sealed record NativePackageAuditEntryFile(
    [property: JsonPropertyName("wingetId")] string WingetId,
    [property: JsonPropertyName("binaryPath")] string? BinaryPath,
    [property: JsonPropertyName("isArm64Native")] bool? IsArm64Native);

[JsonSerializable(typeof(NativePackageAuditFile))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class NativePackageAuditJsonContext : JsonSerializerContext;
