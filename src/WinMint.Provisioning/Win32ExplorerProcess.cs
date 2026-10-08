using System.Diagnostics;

namespace WinMint.Provisioning;

/// <summary>Live explorer.exe process probe + best-effort start (handoff / OOBE dismiss).</summary>
internal static class Win32ExplorerProcess
{
    public static bool IsRunning() => Process.GetProcessesByName("explorer").Length > 0;

    public static void TryStartIfMissing()
    {
        if (IsRunning())
        {
            return;
        }

        try
        {
            string explorer = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "explorer.exe");
            Process.Start(new ProcessStartInfo(explorer) { UseShellExecute = true });
        }
        catch
        {
            // Winlogon may launch explorer on Supervisor exit
        }
    }
}
