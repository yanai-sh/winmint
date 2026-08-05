namespace WinMint.Orchestrator;

/// <summary>
/// Store MSIX pwsh breaks DISM/AppX offline servicing (CTT winutil lesson). Fail closed on Apply.
/// </summary>
public static class PwshHostGuard
{
    /// <summary>True when <paramref name="processPath"/> looks like Microsoft Store PowerShell.</summary>
    public static bool IsStoreMsixPwsh(string? processPath)
    {
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return false;
        }

        string path = processPath.Replace('/', '\\');
        return path.Contains(@"\WindowsApps\Microsoft.PowerShell", StringComparison.OrdinalIgnoreCase)
            || path.Contains(@"\WindowsApps\Microsoft.PowerShellPreview", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Current process path when available (tests pass an explicit path).</summary>
    public static string? CurrentProcessPath()
    {
        try
        {
            return Environment.ProcessPath;
        }
        catch
        {
            return null;
        }
    }
}
