using System.Diagnostics;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

/// <summary>Requests OS reboot after NeedsReboot checkpoint (ticket 16).</summary>
[SupportedOSPlatform("windows")]
public sealed class Win32SystemReboot : ISystemReboot
{
    public void RequestReboot()
    {
        // ponytail: shutdown.exe is enough; ExitWindowsEx + SeShutdownPrivilege if this flakes on metal.
        ProcessStartInfo psi = new()
        {
            FileName = "shutdown.exe",
            ArgumentList = { "/r", "/t", "0", "/f" },
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        _ = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start shutdown.exe for reboot.");
    }
}
