using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Security;
using Windows.Win32.System.Shutdown;

namespace WinMint.Provisioning;

/// <summary>Requests OS reboot after NeedsReboot checkpoint (tickets 16 / 24).</summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class Win32SystemReboot : ISystemReboot
{
    public void RequestReboot()
    {
        try
        {
            EnableSeShutdownPrivilege();
            if (PInvoke.ExitWindowsEx(
                    EXIT_WINDOWS_FLAGS.EWX_REBOOT | EXIT_WINDOWS_FLAGS.EWX_FORCE,
                    (SHUTDOWN_REASON)0))
            {
                return;
            }

            int err = Marshal.GetLastPInvokeError();
            // Fall through to shutdown.exe when ExitWindowsEx refuses (policy / privilege edge).
            FallbackShutdown($"ExitWindowsEx failed: {err}");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            FallbackShutdown(ex.Message);
        }
    }

    private static void FallbackShutdown(string reason)
    {
        try
        {
            _ = Process.Run("shutdown.exe", ["/r", "/t", "0", "/f"], silent: true, timeout: TimeSpan.FromSeconds(30));
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            throw new InvalidOperationException(
                $"Failed to run shutdown.exe for reboot (after: {reason}).",
                ex);
        }
    }

    private static unsafe void EnableSeShutdownPrivilege()
    {
        using SafeFileHandle process = PInvoke.GetCurrentProcess_SafeHandle();
        if (!PInvoke.OpenProcessToken(
                process,
                TOKEN_ACCESS_MASK.TOKEN_ADJUST_PRIVILEGES | TOKEN_ACCESS_MASK.TOKEN_QUERY,
                out SafeFileHandle token))
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "OpenProcessToken failed.");
        }

        using (token)
        {
            if (!PInvoke.LookupPrivilegeValue(null, "SeShutdownPrivilege", out LUID luid))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "LookupPrivilegeValue failed.");
            }

            TOKEN_PRIVILEGES tp = new()
            {
                PrivilegeCount = 1,
            };
            tp.Privileges[0] = new LUID_AND_ATTRIBUTES
            {
                Luid = luid,
                Attributes = TOKEN_PRIVILEGES_ATTRIBUTES.SE_PRIVILEGE_ENABLED,
            };

            if (!PInvoke.AdjustTokenPrivileges(token, false, &tp, default))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "AdjustTokenPrivileges failed.");
            }

            int adjustErr = Marshal.GetLastPInvokeError();
            // ERROR_NOT_ALL_ASSIGNED = 1300
            if (adjustErr == 1300)
            {
                throw new Win32Exception(adjustErr, "SeShutdownPrivilege not assigned.");
            }
        }
    }
}
