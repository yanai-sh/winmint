using WinMint.Contracts;

namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon DMA settle (ADR-003): poll or resume re-verify → hard gate → Ireland DeviceRegion latch →
/// visible restore. Session only starts/branches; Win32 stays behind <see cref="IRegionSnapshot"/> /
/// <see cref="IDmaSetupRegion"/>.
/// </summary>
internal static class DmaSettle
{
    internal enum Mode
    {
        Full,
        Resume,
    }

    internal readonly record struct Outcome(bool HardFailed, bool TimedOut, SessionStatus Status);

    internal static async Task<Outcome> RunAsync(
        Mode mode,
        bool dmaEnabled,
        DmaSettleTarget target,
        IRegionSnapshot region,
        IDmaSetupRegion? dmaSetup,
        TimeProvider time,
        TimeSpan settleDeadline,
        TimeSpan settlePollInterval,
        TimeSpan wallClockTimeout,
        long tenureStartTs,
        Action<SessionStatus> note,
        CancellationToken ct)
    {
        SessionStatus begin = mode == Mode.Resume
            ? new("settle.resumeReverify", "DMA hard-field re-verify on checkpoint resume.")
            : new("settle.begin", "DMA settle start.");
        note(begin);

        if (!dmaEnabled)
        {
            SessionStatus skipped = new("settle.skipped", "DMA disabled; settle skipped.");
            note(skipped);
            return new Outcome(HardFailed: false, TimedOut: false, skipped);
        }

        if (DmaSettleConfidence.TargetIncompleteStatus(target) is SessionStatus incomplete)
        {
            note(incomplete);
            return new Outcome(HardFailed: true, TimedOut: false, incomplete);
        }

        if (mode == Mode.Full)
        {
            try
            {
                region.Apply(target);
            }
            catch (Exception ex)
            {
                SessionStatus applyFailed = new("settle.applyFailed", ex.Message);
                note(applyFailed);
                return new Outcome(HardFailed: true, TimedOut: false, applyFailed);
            }

            Outcome? pollFail = await PollUntilMatchOrBudgetAsync(
                    region,
                    target,
                    time,
                    settleDeadline,
                    settlePollInterval,
                    wallClockTimeout,
                    tenureStartTs,
                    note,
                    ct)
                .ConfigureAwait(false);
            if (pollFail is not null)
            {
                return pollFail.Value;
            }

            if (IsTimedOut(time, tenureStartTs, wallClockTimeout))
            {
                return new Outcome(HardFailed: true, TimedOut: true, TenureTimeoutStatus());
            }
        }

        Outcome? hard = GateHardFields(region, target, note);
        if (hard is not null)
        {
            return hard.Value;
        }

        Outcome? latch = EnsureDeviceRegionForSettle(dmaEnabled, dmaSetup, note);
        if (latch is { HardFailed: true })
        {
            return latch.Value;
        }

        Outcome? afterLatch = RestoreVisibleAfterLatch(region, target, note);
        if (afterLatch is not null)
        {
            return afterLatch.Value;
        }

        if (mode == Mode.Full)
        {
            RegionState postLatch;
            try
            {
                postLatch = region.Read();
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                SessionStatus readFailed = new("settle.readFailed", ex.Message);
                note(readFailed);
                return new Outcome(HardFailed: true, TimedOut: false, readFailed);
            }

            SessionStatus ok = new("settle.ok", "DMA hard fields settled.");
            note(ok);
            if (DmaSettleConfidence.LocationWarnStatus(postLatch, target) is SessionStatus warn)
            {
                note(warn);
            }

            return new Outcome(HardFailed: false, TimedOut: false, ok);
        }

        SessionStatus resumeOk = new("settle.resumeOk", "DMA hard fields re-verified after checkpoint resume.");
        note(resumeOk);
        return new Outcome(HardFailed: false, TimedOut: false, resumeOk);
    }

    private static async Task<Outcome?> PollUntilMatchOrBudgetAsync(
        IRegionSnapshot region,
        DmaSettleTarget target,
        TimeProvider time,
        TimeSpan settleDeadline,
        TimeSpan settlePollInterval,
        TimeSpan wallClockTimeout,
        long tenureStartTs,
        Action<SessionStatus> note,
        CancellationToken ct)
    {
        long settleStartTs = time.GetTimestamp();
        while (true)
        {
            if (ct.IsCancellationRequested)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                note(cancelled);
                return new Outcome(HardFailed: true, TimedOut: false, cancelled);
            }

            if (IsTimedOut(time, tenureStartTs, wallClockTimeout))
            {
                return new Outcome(HardFailed: true, TimedOut: true, TenureTimeoutStatus());
            }

            if (DmaSettleConfidence.TryPollProbe(region, target, out _))
            {
                break;
            }

            TimeSpan settleElapsed = time.GetElapsedTime(settleStartTs);
            TimeSpan tenureElapsed = time.GetElapsedTime(tenureStartTs);
            if (settleElapsed >= settleDeadline || tenureElapsed >= wallClockTimeout)
            {
                break;
            }

            TimeSpan wait = settlePollInterval;
            TimeSpan remainingSettle = settleDeadline - settleElapsed;
            TimeSpan remainingTenure = wallClockTimeout - tenureElapsed;
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
                await Task.Delay(wait, time, ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                SessionStatus cancelled = new("settle.cancelled", "DMA settle cancelled.");
                note(cancelled);
                return new Outcome(HardFailed: true, TimedOut: false, cancelled);
            }
        }

        return null;
    }

    private static Outcome? GateHardFields(
        IRegionSnapshot region,
        DmaSettleTarget target,
        Action<SessionStatus> note)
    {
        RegionState final;
        try
        {
            final = region.Read();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            SessionStatus readFailed = new("settle.readFailed", ex.Message);
            note(readFailed);
            return new Outcome(HardFailed: true, TimedOut: false, readFailed);
        }

        if (!DmaSettleConfidence.HardFieldsMatch(final, target))
        {
            SessionStatus mismatch = DmaSettleConfidence.HardMismatchStatus(final);
            note(mismatch);
            return new Outcome(HardFailed: true, TimedOut: false, mismatch);
        }

        return null;
    }

    private static Outcome? EnsureDeviceRegionForSettle(
        bool dmaEnabled,
        IDmaSetupRegion? dmaSetup,
        Action<SessionStatus> note)
    {
        if (!dmaEnabled)
        {
            return null;
        }

        DmaSetupRegionLatch latch = DmaSettleConfidence.EnsureDmaSetupRegion(
            dmaSetup,
            DmaSetupRegionPolicy.Settle);
        SessionStatus status = DmaSettleConfidence.DeviceRegionStatus(latch);
        note(status);
        return new Outcome(
            HardFailed: DmaSettleConfidence.DeviceRegionHardFailed(latch),
            TimedOut: false,
            status);
    }

    private static Outcome? RestoreVisibleAfterLatch(
        IRegionSnapshot region,
        DmaSettleTarget target,
        Action<SessionStatus> note)
    {
        try
        {
            region.Apply(target);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            SessionStatus applyFailed = new("settle.applyFailed", ex.Message);
            note(applyFailed);
            return new Outcome(HardFailed: true, TimedOut: false, applyFailed);
        }

        return GateHardFields(region, target, note);
    }

    private static bool IsTimedOut(TimeProvider time, long startTimestamp, TimeSpan timeout) =>
        time.GetElapsedTime(startTimestamp) >= timeout;

    private static SessionStatus TenureTimeoutStatus() =>
        new("shell.timeout", "Shell tenure timeout.");
}
