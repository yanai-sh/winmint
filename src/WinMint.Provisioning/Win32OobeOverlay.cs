using System.Diagnostics;
using System.Runtime.Versioning;

using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// Best-effort dismissal of stuck CloudExperienceHost "Just a moment" OOBE overlay after Shell unlock.
/// Autologon + hidden OOBE pages can leave the host running while Winlogon Shell is already explorer.exe.
/// </summary>
[SupportedOSPlatform("windows")]
public static class Win32OobeOverlay
{
    private static readonly string[] OverlayProcessNames = ["CloudExperienceHost", "UserOOBEBroker", "setuphost"];

    public static void TryDismiss()
    {
        TryStampSetupComplete();
        TryTerminateOverlayHosts();
        TryStartExplorerIfMissing();
    }

    /// <summary>
    /// SYSTEM/SetupComplete: mark OOBE complete so CloudExperienceHost does not sit on explorer.
    /// FirstLogon is medium-IL and cannot write these HKLM keys.
    /// </summary>
    public static void TryStampSetupComplete()
    {
        try
        {
            using RegistryKey? setupStatus = Registry.LocalMachine.OpenSubKey(
                @"SYSTEM\Setup\Status",
                writable: true);
            if (setupStatus is not null)
            {
                setupStatus.SetValue("UserOobe", 1, RegistryValueKind.DWord);
                setupStatus.SetValue("OobeInProgress", 0, RegistryValueKind.DWord);
            }

            using RegistryKey? setupState = Registry.LocalMachine.OpenSubKey(
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State",
                writable: true);
            if (setupState is not null)
            {
                setupState.SetValue("ImageState", "IMAGE_STATE_COMPLETE", RegistryValueKind.String);
                setupState.SetValue("SetupPhase", "image_state_complete", RegistryValueKind.String);
            }
        }
        catch
        {
            // ponytail: best-effort — kill overlay hosts still helps when registry is locked
        }
    }

    private static void TryTerminateOverlayHosts()
    {
        foreach (string name in OverlayProcessNames)
        {
            foreach (Process process in Process.GetProcessesByName(name))
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill(entireProcessTree: true);
                    }
                }
                catch
                {
                    // ponytail: another session or protected host — continue
                }
                finally
                {
                    process.Dispose();
                }
            }
        }
    }

    private static void TryStartExplorerIfMissing()
    {
        if (Process.GetProcessesByName("explorer").Length > 0)
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
