using System.Text.Json.Serialization;

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

            // Settle already ran before NeedsReboot, but reboot can still drift locale/Geo/TZ.
            // Re-read hard fields once (no poll/apply churn) before jobs; DeviceRegion latch stays.
            DmaSettle.Outcome resumeSettle = await RunDmaSettleAsync(
                    DmaSettle.Mode.Resume,
                    bundle,
                    env,
                    phases,
                    tenureStartTs,
                    ct)
                .ConfigureAwait(false);
            if (resumeSettle.HardFailed)
            {
                return await FailOpenAsync(
                        bundle,
                        env,
                        phases,
                        emitted,
                        resumeSettle.Status,
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

            DmaSettle.Outcome settle = await RunDmaSettleAsync(
                    DmaSettle.Mode.Full,
                    bundle,
                    env,
                    phases,
                    tenureStartTs,
                    ct)
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
            SessionStatus? network = await EnsureNetworkAvailableAsync(
                    bundle,
                    env,
                    phases,
                    tenureStartTs,
                    ct)
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
                Guest: env.Guest,
                RemoveProvisionedAppx: bundle.RemoveProvisionedAppx ?? [],
                Time: env.Time,
                ReportStatus: status => Note(env, phases, status),
                Evidence: env.Evidence,
                PackageStrict: bundle.PackageStrict,
                WallClockTimeout: bundle.Policy.WallClockTimeout,
                TenureStartTimestamp: tenureStartTs,
                StartIndex: jobStartIndex,
                WslMock: new WslMockState());
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
            // Unattend LogonCount=5 is a hard autologon budget; re-arm so NeedsReboot
            // jobs cannot land on a password prompt before the next Shell tenure.
            env.Guest.Winlogon.ReArmAutoLogonCount();
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

        // Finishing: handoff → Complete. (No AppearanceOnce until Profile appearance grilled.)
        env.Guest.Checkpoints.ClearCheckpoint();

        // Unlock before Complete evidence so S4 never claims green while Shell is still Supervisor.
        if (!ShellTenureEntry.TryApplyLive(
                env.Guest.Winlogon,
                TenureExit.Complete,
                dismissOobe: env.Guest.TryDismissOobeOverlay,
                notePhase: status => Note(env, phases, status)))
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

        try
        {
            _ = env.Guest.ApplyShellChrome(
                new ShellChromeRequest(
                    FailOpen: true,
                    SelectedWingetIds: [],
                    RequireSelectedPins: false));
        }
        catch (Exception)
        {
            // ponytail: evidence already durable; fail-open chrome is best-effort (same as oobe.dismiss)
        }

        // Unlock after evidence — custom Shell is medium-IL and may lack HKLM write.
        _ = ShellTenureEntry.TryApplyLive(
            env.Guest.Winlogon,
            TenureExit.FailOpen,
            dismissOobe: env.Guest.TryDismissOobeOverlay);

        return new SessionResult(SessionOutcome.Failed, status, emitted);
    }

    private static async Task<SessionStatus?> EnsureNetworkAvailableAsync(
        ProvisioningBundle bundle,
        ShellEnvironment env,
        List<string> phases,
        long tenureStartTs,
        CancellationToken ct)
    {
        if (env.Guest.Connectivity is null)
        {
            SessionStatus offline = new(
                "network.required.offline",
                "Plan requires network but outbound connectivity probe failed.");
            Note(env, phases, offline);
            return offline;
        }

        SessionStatus begin = new("network.begin", "Waiting for outbound connectivity.");
        Note(env, phases, begin);

        long networkStartTs = env.Time.GetTimestamp();
        TimeSpan deadline = bundle.Policy.NetworkDeadline;
        TimeSpan poll = bundle.Policy.NetworkPollInterval <= TimeSpan.Zero
            ? TimeSpan.FromSeconds(2)
            : bundle.Policy.NetworkPollInterval;

        while (true)
        {
            if (ct.IsCancellationRequested)
            {
                SessionStatus cancelled = new("network.cancelled", "Network wait cancelled.");
                Note(env, phases, cancelled);
                return cancelled;
            }

            if (IsTimedOut(env, tenureStartTs, bundle.Policy.WallClockTimeout))
            {
                return TimeoutStatus();
            }

            if (await env.Guest.Connectivity.HasOutboundNetworkAsync(ct).ConfigureAwait(false))
            {
                SessionStatus ok = new("network.ok", "Outbound connectivity available.");
                Note(env, phases, ok);
                return null;
            }

            if (deadline <= TimeSpan.Zero
                || env.Time.GetElapsedTime(networkStartTs) >= deadline)
            {
                break;
            }

            TimeSpan elapsed = env.Time.GetElapsedTime(networkStartTs);
            TimeSpan wait = poll;
            TimeSpan remainingNetwork = deadline - elapsed;
            TimeSpan remainingTenure = bundle.Policy.WallClockTimeout - env.Time.GetElapsedTime(tenureStartTs);
            if (remainingNetwork < wait)
            {
                wait = remainingNetwork;
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
                SessionStatus cancelled = new("network.cancelled", "Network wait cancelled.");
                Note(env, phases, cancelled);
                return cancelled;
            }
        }

        SessionStatus failed = new(
            "network.required.offline",
            "Plan requires network but outbound connectivity probe failed.");
        Note(env, phases, failed);
        return failed;
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

    private static Task<DmaSettle.Outcome> RunDmaSettleAsync(
        DmaSettle.Mode mode,
        ProvisioningBundle bundle,
        ShellEnvironment env,
        List<string> phases,
        long tenureStartTs,
        CancellationToken ct) =>
        DmaSettle.RunAsync(
            mode,
            bundle.DmaEnabled,
            bundle.Dma,
            env.Guest.Region,
            env.Guest.DmaSetup,
            env.Time,
            bundle.Policy.SettleDeadline,
            bundle.Policy.SettlePollInterval,
            bundle.Policy.WallClockTimeout,
            tenureStartTs,
            status => Note(env, phases, status),
            ct);

    private static SessionResult? EnsureDmaSetupRegionForMachineSetup(MachineSetupEnvironment env)
    {
        DmaSetupRegionLatch latch = EnsureDmaSetupRegion(
            env.DmaSetup,
            DmaSetupRegionPolicy.MachineSetup);
        return latch.Kind switch
        {
            DmaSetupRegionLatchKind.Ok or DmaSetupRegionLatchKind.AccessDeniedSoft => null,
            DmaSetupRegionLatchKind.MissingPort => Fail(
                "machineSetup.dmaSetupRegionFailed",
                "DmaSetup port required when DMA enabled."),
            _ => Fail("machineSetup.dmaSetupRegionFailed", latch.Message ?? "DeviceRegion latch failed."),
        };
    }

    internal static DmaSetupRegionLatch EnsureDmaSetupRegion(
        IDmaSetupRegion? port,
        DmaSetupRegionPolicy policy) =>
        DmaSettleConfidence.EnsureDmaSetupRegion(port, policy);

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

            // SYSTEM can write HKLM ConsentStore; FirstLogon medium-IL cannot.
            if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 19041)
                && bundle.Dma.LocationServicesEnabled is bool locationEnabled)
            {
                _ = Win32RegionSnapshot.TrySetLocationServices(locationEnabled);
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

        if (env.StampOobeComplete is not null)
        {
            try
            {
                env.StampOobeComplete();
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // ponytail: SYSTEM ImageState stamp is best-effort; Shell TryDismiss still runs
                _ = ex;
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
