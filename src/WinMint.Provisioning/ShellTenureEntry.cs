namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon tenure exit: outcome → Winlogon Shell stamp and process exit code.
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
    /// Stamp Shell for a tenure exit and return the process exit code.
    /// Reboot leaves Shell untouched; every other exit unlocks to explorer.
    /// Complete returns 0 only when Shell is explorer after unlock.
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
}
