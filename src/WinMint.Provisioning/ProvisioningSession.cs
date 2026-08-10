namespace WinMint.Provisioning;

using System.Text.Json.Serialization;
using WinMint.Contracts;

public static partial class ProvisioningSession
{
    public const string ForbiddenAutologonUser = "defaultuser0";
    public const string EvidenceSchemaVersion = "winmint.provisioning.evidence/v1";
    public const string PackagesEvidenceSchemaVersion = "winmint.packages.evidence/v1";
    public const string ExplorerShell = "explorer.exe";

    /// <summary>App Installer / winget package family (Microsoft-documented FirstLogon register target).</summary>
    public const string DesktopAppInstallerFamilyName = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe";

    /// <summary>Run MachineSetup or Shell tenure for a provisioning bundle against the live guest environment.</summary>
    public static async Task<SessionResult> RunAsync(
        SessionMode mode,
        ProvisioningBundle bundle,
        SessionEnvironment env,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(bundle);
        ArgumentNullException.ThrowIfNull(env);

        return mode switch
        {
            SessionMode.MachineSetup => await RunMachineSetupAsync(bundle, env, ct).ConfigureAwait(false),
            SessionMode.Shell => await RunShellAsync(bundle, env, ct).ConfigureAwait(false),
            _ => new SessionResult(
                SessionOutcome.Failed,
                new SessionStatus("session.mode.unknown", $"Unknown mode: {mode}"),
                []),
        };
    }

    private static async Task<SessionResult> RunShellAsync(
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
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.cancelled", "Shell tenure cancelled."),
                dwell: false,
                firstPaintMs).ConfigureAwait(false);
        }

        if (env.Evidence is null)
        {
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus("shell.evidence.required", "Shell tenure requires a write-only evidence sink."),
                dwell: false,
                firstPaintMs).ConfigureAwait(false);
        }

        // Bootstrap: in-progress checkpoint + missing/stale heartbeat ⇒ fail-open.
        TenureState tenure = env.Checkpoints.ReadTenure();
        CheckpointState? storedCheckpoint = env.Checkpoints.TryReadCheckpoint();
        if (tenure.CheckpointInProgress && IsStaleHeartbeat(bundle, env, tenure))
        {
            env.Checkpoints.ClearCheckpoint();
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
            env.Checkpoints.ClearCheckpoint();
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
            JobsPhaseResult? network = await JobRunner.EnsureNetworkAvailableAsync(bundle, env, phases, ct)
                .ConfigureAwait(false);
            if (network is not null)
            {
                return await FailOpenAsync(
                        bundle,
                        env,
                        phases,
                        emitted,
                        network.Value.Status,
                        dwell: true,
                        firstPaintMs)
                    .ConfigureAwait(false);
            }
        }

        JobsPhaseResult jobs;
        try
        {
            jobs = await JobRunner.ExecuteAsync(bundle, env, phases, tenureStartTs, jobStartIndex, ct)
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

        if (jobs.TimedOut)
        {
            return await FailOpenAsync(bundle, env, phases, emitted, TimeoutStatus(), dwell: true, firstPaintMs)
                .ConfigureAwait(false);
        }

        if (jobs.Outcome == SessionOutcome.Failed)
        {
            return await FailOpenAsync(bundle, env, phases, emitted, jobs.Status, dwell: true, firstPaintMs)
                .ConfigureAwait(false);
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
            return await FailOpenAsync(
                bundle,
                env,
                phases,
                emitted,
                new SessionStatus(
                    "shell.unlock_failed",
                    "Winlogon Shell was not restored to explorer.exe after jobs."),
                dwell: true,
                firstPaintMs).ConfigureAwait(false);
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

    private static async Task<SessionResult> FailOpenAsync(
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
                await Task.Delay(bundle.Policy.FailedDwell, env.Time, CancellationToken.None)
                    .ConfigureAwait(false);
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

    private readonly record struct SettlePhaseResult(bool HardFailed, bool TimedOut, SessionStatus Status);

    /// <summary>
    /// Bounded restore + poll; only the final snapshot gates hard locale / GeoID / TZ.
    /// Soft location-services mismatch warns and continues.
    /// </summary>
    private static async Task<SettlePhaseResult> RunSettleAsync(
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
                await Task.Delay(wait, env.Time, ct).ConfigureAwait(false);
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

    private static Task<SessionResult> RunMachineSetupAsync(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        CancellationToken ct)
    {
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
            return Task.FromResult(Fail("machineSetup.autologon.stamp_failed", ex.Message));
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
                return Task.FromResult(Fail("machineSetup.secret_wipe_failed", ex.Message));
            }
        }

        if (shellFailure is not null)
        {
            return Task.FromResult(shellFailure);
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
