namespace WinMint.Provisioning;

public static class ProvisioningSession
{
    public const string ForbiddenAutologonUser = "defaultuser0";
    public const string EvidenceSchemaVersion = "winmint.provisioning.evidence/v1";

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
        if (ct.IsCancellationRequested)
        {
            return Fail("shell.cancelled", "Shell tenure cancelled.");
        }

        if (env.Evidence is null)
        {
            return Fail("shell.evidence.required", "Shell tenure requires a write-only evidence sink.");
        }

        List<string> phases = [];
        List<EvidenceSnapshot> emitted = [];

        // FirstPaint — opaque frame before any settle work (S3 order; S4 measures latency).
        env.Splash.Show();
        SessionStatus paintStatus = new("shell.first_paint", "First opaque splash frame.");
        env.Splash.SetStatus(paintStatus);
        phases.Add(paintStatus.Code);

        SettlePhaseResult settle = RunSettle(bundle, env, phases, ct);
        if (settle.HardFailed)
        {
            // Jobs never start after hard settle failure.
            EvidenceSnapshot failSnap = env.Evidence.Write(
                new ProvisioningEvidenceDocument(
                    SchemaVersion: EvidenceSchemaVersion,
                    Outcome: SessionOutcome.Failed.ToString(),
                    StatusCode: settle.Status.Code,
                    StatusMessage: settle.Status.Message,
                    Phases: phases));
            emitted.Add(failSnap);
            return new SessionResult(SessionOutcome.Failed, settle.Status, emitted);
        }

        // ponytail: unlock/appearance = ticket 07; checkpoint reboot = ticket 08
        JobsPhaseResult jobs = RunJobs(bundle, env, phases, ct);
        EvidenceSnapshot snap = env.Evidence.Write(
            new ProvisioningEvidenceDocument(
                SchemaVersion: EvidenceSchemaVersion,
                Outcome: jobs.Outcome.ToString(),
                StatusCode: jobs.Status.Code,
                StatusMessage: jobs.Status.Message,
                Phases: phases));
        emitted.Add(snap);

        return new SessionResult(jobs.Outcome, jobs.Status, emitted);
    }

    private readonly record struct JobsPhaseResult(SessionOutcome Outcome, SessionStatus Status);

    private static JobsPhaseResult RunJobs(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        List<string> phases,
        CancellationToken ct)
    {
        SessionStatus begin = new("jobs.begin", "Provisioning jobs start.");
        env.Splash.SetStatus(begin);
        phases.Add(begin.Code);

        foreach (ProvisionJob job in bundle.Jobs)
        {
            ct.ThrowIfCancellationRequested();

            if (!string.Equals(job.Kind, "stub", StringComparison.OrdinalIgnoreCase))
            {
                SessionStatus unsupported = new(
                    "jobs.kind.unsupported",
                    $"Unsupported job kind '{job.Kind}' for id '{job.Id}'.");
                env.Splash.SetStatus(unsupported);
                phases.Add(unsupported.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, unsupported);
            }

            ProcessStartResult started;
            try
            {
                started = env.Processes.Run("cmd.exe", ["/c", "exit", "0"], ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus spawnFailed = new("jobs.spawn_failed", $"{job.Id}: {ex.Message}");
                env.Splash.SetStatus(spawnFailed);
                phases.Add(spawnFailed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, spawnFailed);
            }

            if (started.ExitCode != 0)
            {
                SessionStatus failed = new(
                    "jobs.failed",
                    $"Job '{job.Id}' exited {started.ExitCode}.");
                env.Splash.SetStatus(failed);
                phases.Add(failed.Code);
                return new JobsPhaseResult(SessionOutcome.Failed, failed);
            }
        }

        SessionStatus ok = new("jobs.ok", "Provisioning jobs completed.");
        env.Splash.SetStatus(ok);
        phases.Add(ok.Code);
        return new JobsPhaseResult(SessionOutcome.Complete, ok);
    }

    private readonly record struct SettlePhaseResult(bool HardFailed, SessionStatus Status);

    /// <summary>
    /// Bounded restore + poll; only the final snapshot gates hard locale / GeoID / TZ.
    /// Soft location-services mismatch warns and continues.
    /// </summary>
    private static SettlePhaseResult RunSettle(
        ProvisioningBundle bundle,
        SessionEnvironment env,
        List<string> phases,
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
            return new SettlePhaseResult(HardFailed: false, skipped);
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
            return new SettlePhaseResult(HardFailed: true, incomplete);
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
            return new SettlePhaseResult(HardFailed: true, applyFailed);
        }

        DateTimeOffset deadline = env.Time.GetUtcNow() + bundle.Policy.SettleDeadline;

        while (true)
        {
            if (ct.IsCancellationRequested)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                env.Splash.SetStatus(cancelled);
                phases.Add(cancelled.Code);
                return new SettlePhaseResult(HardFailed: true, cancelled);
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
                // Intermediate probe failures are non-authoritative.
                _ = ex;
            }

            DateTimeOffset now = env.Time.GetUtcNow();
            if (now >= deadline)
            {
                break;
            }

            TimeSpan wait = bundle.Policy.SettlePollInterval;
            TimeSpan remaining = deadline - now;
            if (remaining < wait)
            {
                wait = remaining;
            }

            if (wait <= TimeSpan.Zero)
            {
                break;
            }

            try
            {
                Task.Delay(wait, env.Time, ct).GetAwaiter().GetResult();
            }
            catch (OperationCanceledException)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                env.Splash.SetStatus(cancelled);
                phases.Add(cancelled.Code);
                return new SettlePhaseResult(HardFailed: true, cancelled);
            }
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
            return new SettlePhaseResult(HardFailed: true, readFailed);
        }

        if (!HardFieldsMatch(final, bundle.Dma))
        {
            SessionStatus mismatch = new(
                "settle.hard_mismatch",
                $"Final snapshot hard fields mismatch (locale={final.Locale}, geoId={final.GeoId}, tz={final.TimeZoneId}).");
            env.Splash.SetStatus(mismatch);
            phases.Add(mismatch.Code);
            return new SettlePhaseResult(HardFailed: true, mismatch);
        }

        if (bundle.Dma.LocationServicesEnabled is bool expectedLocation
            && final.LocationServicesEnabled != expectedLocation)
        {
            SessionStatus warn = new(
                "settle.location_warn",
                $"Location-services posture is {final.LocationServicesEnabled}; expected {expectedLocation}.");
            env.Splash.SetStatus(warn);
            phases.Add(warn.Code);
            return new SettlePhaseResult(HardFailed: false, warn);
        }

        SessionStatus ok = new("settle.ok", "DMA hard fields settled.");
        env.Splash.SetStatus(ok);
        phases.Add(ok.Code);
        return new SettlePhaseResult(HardFailed: false, ok);
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

        try
        {
            env.Secrets.Wipe(scrubbedView);
        }
        catch (Exception ex)
        {
            return Fail("machineSetup.secret_wipe_failed", ex.Message);
        }

        if (shellFailure is not null)
        {
            return shellFailure;
        }

        return new SessionResult(
            SessionOutcome.Complete,
            new SessionStatus("machineSetup.ok", "Autologon stamped; Shell verified; secrets wiped."),
            []);
    }

    private static bool ShellEquals(string? actual, string expected) =>
        !string.IsNullOrWhiteSpace(actual)
        && string.Equals(actual.Trim(), expected.Trim(), StringComparison.OrdinalIgnoreCase);

    private static SessionResult Fail(string code, string message) =>
        new(SessionOutcome.Failed, new SessionStatus(code, message), []);
}
