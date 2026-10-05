namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon tenure exit / Provisioning handoff: outcome → Winlogon Shell stamp,
/// OOBE overlay dismiss, and process exit code.
/// Fail-open (missing bundle, load fail, crash, session Failed) and Complete unlock to
/// explorer; Reboot withholds so Supervisor stays Shell for resume.
/// </summary>
public enum TenureExit
{
    Complete,
    Reboot,
    FailOpen,
}

public static class ShellTenureEntry
{
    public static TenureExit FromSession(SessionOutcome outcome) => outcome switch
    {
        SessionOutcome.Complete => TenureExit.Complete,
        SessionOutcome.Reboot => TenureExit.Reboot,
        _ => TenureExit.FailOpen,
    };

    /// <summary>
    /// Live handoff during Shell tenure (before Complete evidence, or after Failed evidence).
    /// Complete requires explorer Shell after unlock; FailOpen unlocks best-effort; Reboot is a no-op.
    /// </summary>
    /// <returns>false when Complete unlock/verify failed (caller should FailOpen).</returns>
    public static bool TryApplyLive(
        IWinlogonRegistry winlogon,
        TenureExit exit,
        Action? dismissOobe = null,
        Action<SessionStatus>? notePhase = null)
    {
        ArgumentNullException.ThrowIfNull(winlogon);
        if (exit == TenureExit.Reboot)
        {
            return true;
        }

        bool unlocked = TryUnlock(winlogon);
        if (exit == TenureExit.Complete)
        {
            if (!unlocked || !IsExplorerShell(winlogon.GetShell()))
            {
                return false;
            }

            TryDismissOobe(dismissOobe, notePhase);
            return true;
        }

        // FailOpen: unlock may fail under medium-IL; dismiss only when unlock landed.
        if (unlocked)
        {
            TryDismissOobe(dismissOobe, notePhase);
        }

        return unlocked;
    }

    /// <summary>
    /// Stamp Shell for a tenure exit and return the process exit code.
    /// Reboot leaves Shell untouched; every other exit unlocks to explorer.
    /// Complete returns 0 only when Shell is explorer after unlock.
    /// Idempotent with <see cref="TryApplyLive"/> when Session already unlocked.
    /// </summary>
    public static int Apply(IWinlogonRegistry winlogon, TenureExit exit)
    {
        ArgumentNullException.ThrowIfNull(winlogon);
        if (exit == TenureExit.Reboot)
        {
            return 1;
        }

        _ = TryUnlock(winlogon);
        if (exit == TenureExit.Complete && IsExplorerShell(winlogon.GetShell()))
        {
            return 0;
        }

        return 1;
    }

    public static bool IsExplorerShell(string? shell) =>
        !string.IsNullOrWhiteSpace(shell)
        && shell.Trim().Equals(ProvisioningSession.ExplorerShell, StringComparison.OrdinalIgnoreCase);

    /// <returns>true when SetShell(explorer) did not throw.</returns>
    public static bool TryUnlock(IWinlogonRegistry winlogon)
    {
        ArgumentNullException.ThrowIfNull(winlogon);
        try
        {
            winlogon.SetShell(ProvisioningSession.ExplorerShell);
            return true;
        }
        catch (Exception)
        {
            // ponytail: evidence already durable; MachineSetup grants unlock ACL for Shell
            return false;
        }
    }

    private static void TryDismissOobe(Action? dismissOobe, Action<SessionStatus>? notePhase)
    {
        if (dismissOobe is null)
        {
            return;
        }

        try
        {
            dismissOobe();
            notePhase?.Invoke(
                new SessionStatus(
                    "oobe.dismiss",
                    "Dismissed stuck CloudExperienceHost OOBE overlay."));
        }
        catch (Exception)
        {
            // ponytail: unlock already durable; overlay teardown is best-effort
        }
    }
}
