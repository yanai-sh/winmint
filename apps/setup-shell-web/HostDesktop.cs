using System.Runtime.InteropServices;
using System.Text;

namespace WinMintSetupShell;

internal static partial class NativeMethods
{
    public const int SW_HIDE = 0;
    public const int SW_SHOW = 5;
    public const int VK_ESCAPE = 0x1B;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const nint HWND_TOPMOST = -1;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const uint MONITOR_DEFAULTTOPRIMARY = 0x00000001;

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public int Width => Right - Left;
        public int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MONITORINFO
    {
        public int Size;
        public RECT Monitor;
        public RECT Work;
        public uint Flags;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern nint FindWindow(string? className, string? windowName);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(nint hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, nuint dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(nint hWnd);

    [DllImport("user32.dll")]
    public static extern nint MonitorFromPoint(POINT pt, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetMonitorInfoW(nint hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);

    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
}

internal static class MonitorUtil
{
    public static NativeMethods.RECT GetPrimaryMonitorBounds()
    {
        var pt = new NativeMethods.POINT { X = 0, Y = 0 };
        var monitor = NativeMethods.MonitorFromPoint(pt, NativeMethods.MONITOR_DEFAULTTOPRIMARY);
        var info = new NativeMethods.MONITORINFO
        {
            Size = Marshal.SizeOf<NativeMethods.MONITORINFO>()
        };
        if (monitor != nint.Zero && NativeMethods.GetMonitorInfoW(monitor, ref info))
        {
            return info.Monitor;
        }

        return new NativeMethods.RECT
        {
            Left = 0,
            Top = 0,
            Right = NativeMethods.GetSystemMetrics(NativeMethods.SM_CXSCREEN),
            Bottom = NativeMethods.GetSystemMetrics(NativeMethods.SM_CYSCREEN)
        };
    }

    public static void ApplyFullscreenBounds(nint hwnd, NativeMethods.RECT bounds)
    {
        if (hwnd == nint.Zero)
        {
            return;
        }

        NativeMethods.SetWindowPos(
            hwnd,
            NativeMethods.HWND_TOPMOST,
            bounds.Left,
            bounds.Top,
            bounds.Width,
            bounds.Height,
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
    }
}

internal static class DesktopGuard
{
    public static void HideTaskbars()
    {
        foreach (var cls in new[] { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" })
        {
            var h = NativeMethods.FindWindow(cls, null);
            if (h != nint.Zero)
            {
                NativeMethods.ShowWindow(h, NativeMethods.SW_HIDE);
            }
        }
    }

    public static void ShowTaskbars()
    {
        foreach (var cls in new[] { "Shell_TrayWnd", "Shell_SecondaryTrayWnd" })
        {
            var h = NativeMethods.FindWindow(cls, null);
            if (h != nint.Zero)
            {
                NativeMethods.ShowWindow(h, NativeMethods.SW_SHOW);
            }
        }
    }

    public static void DismissStartMenu()
    {
        NativeMethods.keybd_event(NativeMethods.VK_ESCAPE, 0, 0, 0);
        NativeMethods.keybd_event(NativeMethods.VK_ESCAPE, 0, NativeMethods.KEYEVENTF_KEYUP, 0);
    }

    public static void Tick(nint hostWindow, bool preview)
    {
        if (preview)
        {
            if (hostWindow != nint.Zero)
            {
                MonitorUtil.ApplyFullscreenBounds(hostWindow, MonitorUtil.GetPrimaryMonitorBounds());
            }
            return;
        }

        HideTaskbars();
        DismissStartMenu();
        if (hostWindow != nint.Zero)
        {
            MonitorUtil.ApplyFullscreenBounds(hostWindow, MonitorUtil.GetPrimaryMonitorBounds());
            NativeMethods.SetForegroundWindow(hostWindow);
        }
    }

    public static void ClearNoWinKeys()
    {
        try
        {
            using var proc = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "reg.exe",
                Arguments = "delete HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer /v NoWinKeys /f",
                CreateNoWindow = true,
                UseShellExecute = false
            });
            proc?.WaitForExit(3000);
        }
        catch { }
    }

    public static void ClearDisableTaskSwitching()
    {
        try
        {
            using var proc = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "reg.exe",
                Arguments = "delete HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System /v DisableTaskSwitching /f",
                CreateNoWindow = true,
                UseShellExecute = false
            });
            proc?.WaitForExit(3000);
        }
        catch { }
    }
}

internal sealed class ShellLogger
{
    private readonly string _path;
    private readonly object _gate = new();

    public ShellLogger(string logDir, bool enabled)
    {
        _path = enabled ? Path.Combine(logDir, "SetupShell.log") : "";
        if (enabled)
        {
            Directory.CreateDirectory(logDir);
        }
    }

    public void Info(string message)
    {
        if (string.IsNullOrEmpty(_path))
        {
            return;
        }

        var line = $"{DateTimeOffset.Now:O} {message}";
        lock (_gate)
        {
            File.AppendAllText(_path, line + Environment.NewLine, Encoding.UTF8);
        }
    }
}
