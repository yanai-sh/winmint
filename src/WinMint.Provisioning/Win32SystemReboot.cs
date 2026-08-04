using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

/// <summary>Requests OS reboot after NeedsReboot checkpoint (tickets 16 / 24).</summary>
[SupportedOSPlatform("windows")]
public sealed partial class Win32SystemReboot : ISystemReboot
{
    private const uint EwxReboot = 0x00000002;
    private const uint EwxForce = 0x00000004;
    private const uint TokenAdjustPrivileges = 0x0020;
    private const uint TokenQuery = 0x0008;
    private const uint SePrivilegeEnabled = 0x00000002;

    public void RequestReboot()
    {
        try
        {
            EnableSeShutdownPrivilege();
            if (ExitWindowsEx(EwxReboot | EwxForce, 0))
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
        ProcessStartInfo psi = new()
        {
            FileName = "shutdown.exe",
            ArgumentList = { "/r", "/t", "0", "/f" },
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        _ = Process.Start(psi)
            ?? throw new InvalidOperationException(
                $"Failed to start shutdown.exe for reboot (after: {reason}).");
    }

    private static void EnableSeShutdownPrivilege()
    {
        if (!OpenProcessToken(GetCurrentProcess(), TokenAdjustPrivileges | TokenQuery, out nint token))
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "OpenProcessToken failed.");
        }

        try
        {
            if (!LookupPrivilegeValueW(null, "SeShutdownPrivilege", out Luid luid))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError(), "LookupPrivilegeValue failed.");
            }

            TokenPrivileges tp = new()
            {
                PrivilegeCount = 1,
                Privileges = new LuidAndAttributes
                {
                    Luid = luid,
                    Attributes = SePrivilegeEnabled,
                },
            };

            if (!AdjustTokenPrivileges(token, false, ref tp, 0, nint.Zero, nint.Zero))
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
        finally
        {
            CloseHandle(token);
        }
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ExitWindowsEx(uint uFlags, uint dwReason);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool OpenProcessToken(
        nint processHandle,
        uint desiredAccess,
        out nint tokenHandle);

    [LibraryImport("advapi32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool LookupPrivilegeValueW(
        string? lpSystemName,
        string lpName,
        out Luid lpLuid);

    [LibraryImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AdjustTokenPrivileges(
        nint tokenHandle,
        [MarshalAs(UnmanagedType.Bool)] bool disableAllPrivileges,
        ref TokenPrivileges newState,
        uint bufferLength,
        nint previousState,
        nint returnLength);

    [LibraryImport("kernel32.dll")]
    private static partial nint GetCurrentProcess();

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CloseHandle(nint hObject);

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LuidAndAttributes
    {
        public Luid Luid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenPrivileges
    {
        public uint PrivilegeCount;
        public LuidAndAttributes Privileges;
    }
}
