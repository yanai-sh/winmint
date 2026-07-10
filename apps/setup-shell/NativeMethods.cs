using System.Runtime.InteropServices;
using System.Text;

namespace WinMintSetupShell;

internal static partial class NativeMethods
{
    public const int SW_HIDE = 0;
    public const int SW_SHOW = 5;
    public const int VK_ESCAPE = 0x1B;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const int GWL_EXSTYLE = -20;
    public const nint HWND_TOPMOST = -1;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const uint MONITOR_DEFAULTTOPRIMARY = 0x00000001;
    public const int WS_EX_TOPMOST = 0x00000008;
    public const int WS_POPUP = unchecked((int)0x80000000);
    public const int WS_VISIBLE = 0x10000000;
    public const int WM_DESTROY = 0x0002;
    public const int WM_ACTIVATE = 0x0006;
    public const int WM_TIMER = 0x0113;
    public const int WM_PAINT = 0x000F;
    public const int WM_KEYDOWN = 0x0100;
    public const int WM_DISPLAYCHANGE = 0x007E;
    public const int WM_DPICHANGED = 0x02E0;
    public const int PM_REMOVE = 0x0001;
    public const uint TIMER_ID = 1;
    public const uint ANIM_TIMER_ID = 2;

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public nint Hwnd;
        public uint Message;
        public nuint WParam;
        public nint LParam;
        public uint Time;
        public int PtX;
        public int PtY;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern nint CreateWindowExW(
        int exStyle, string className, string windowName, int style,
        int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern ushort RegisterClassExW(ref WNDCLASSEXW lpwcx);

    [DllImport("user32.dll")]
    public static extern bool DestroyWindow(nint hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(nint hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern int ShowCursor(bool bShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(nint hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetMessageW(out MSG lpMsg, nint hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    public static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    public static extern nint DispatchMessageW(ref MSG lpMsg);

    [DllImport("user32.dll")]
    public static extern bool PostQuitMessage(int nExitCode);

    [DllImport("user32.dll")]
    public static extern nint DefWindowProcW(nint hWnd, uint msg, nuint wParam, nint lParam);

    [DllImport("user32.dll")]
    public static extern bool SetTimer(nint hWnd, nuint id, uint elapse, nint timerProc);

    [DllImport("user32.dll")]
    public static extern bool KillTimer(nint hWnd, nuint id);

    [DllImport("user32.dll")]
    public static extern bool InvalidateRect(nint hWnd, nint rect, bool erase);

    [DllImport("user32.dll")]
    public static extern nint BeginPaint(nint hWnd, out PAINTSTRUCT lpPaint);

    [DllImport("user32.dll")]
    public static extern bool EndPaint(nint hWnd, ref PAINTSTRUCT lpPaint);

    [StructLayout(LayoutKind.Sequential)]
    public struct PAINTSTRUCT
    {
        public nint Hdc;
        public int Erase;
        public RECT Paint;
        public int Restore;
        public int IncUpdate;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
        public byte[] Reserved;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern nint FindWindow(string? className, string? windowName);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, nuint dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    public static extern nint MonitorFromPoint(POINT pt, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetMonitorInfoW(nint hMonitor, ref MONITORINFO lpmi);

    public delegate bool MonitorEnumProc(nint hMonitor, nint hdcMonitor, ref RECT lprcMonitor, nint dwData);

    [DllImport("user32.dll")]
    public static extern bool EnumDisplayMonitors(nint hdc, nint lprcClip, MonitorEnumProc lpfnEnum, nint dwData);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        nint hWnd, nint hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    [DllImport("gdi32.dll")]
    public static extern nint CreateSolidBrush(int color);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(nint hObject);

    [DllImport("gdi32.dll")]
    public static extern bool FillRect(nint hdc, ref RECT rect, nint brush);

    [DllImport("gdi32.dll")]
    public static extern int SetBkMode(nint hdc, int mode);

    [DllImport("gdi32.dll")]
    public static extern int SetTextColor(nint hdc, int color);

    [DllImport("gdi32.dll")]
    public static extern nint SelectObject(nint hdc, nint hgdiobj);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern nint CreateFontW(
        int height, int width, int escapement, int orientation, int weight,
        byte italic, byte underline, byte strikeOut, byte charSet,
        byte outputPrecision, byte clipPrecision, byte quality,
        byte pitchAndFamily, string faceName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int DrawTextW(nint hdc, string text, int length, ref RECT rect, uint format);

    public const int TRANSPARENT = 1;
    public const int FW_NORMAL = 400;
    public const int FW_SEMIBOLD = 600;
    public const byte DEFAULT_CHARSET = 1;
    public const byte OUT_DEFAULT_PRECIS = 0;
    public const byte CLIP_DEFAULT_PRECIS = 0;
    public const byte CLEARTYPE_QUALITY = 5;
    public const byte DEFAULT_PITCH = 0;
    public const uint DT_LEFT = 0x0000;
    public const uint DT_CENTER = 0x0001;
    public const uint DT_TOP = 0x0000;
    public const uint DT_WORDBREAK = 0x0010;
    public const uint DT_NOPREFIX = 0x0800;

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(nint hWnd, out RECT rect);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MONITORINFO
    {
        public int Size;
        public RECT Monitor;
        public RECT Work;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    public static extern bool AdjustWindowRectEx(ref RECT rect, int style, bool menu, int exStyle);

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
    public struct WNDCLASSEXW
    {
        public uint Size;
        public uint Style;
        public nint WndProc;
        public int ClsExtra;
        public int WndExtra;
        public nint Instance;
        public nint Icon;
        public nint Cursor;
        public nint Background;
        public nint MenuName;
        public string ClassName;
        public nint IconSm;
    }
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

    public static void Tick(nint hostWindow, SecondaryMonitorCover? secondaryCovers = null)
    {
        HideTaskbars();
        DismissStartMenu();
        secondaryCovers?.ApplyBounds();
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
        catch
        {
            // best-effort mirror of Disable-WinMintSetupShellDesktopGuard
        }
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
        catch
        {
            // best-effort mirror of Disable-WinMintProvisioningGuard
        }
    }
}

internal sealed class ShellLogger
{
    private readonly string _path;
    private readonly object _gate = new();

    public ShellLogger(string logDir, bool enabled)
    {
        _path = enabled
            ? Path.Combine(logDir, "SetupShell.log")
            : "";
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

internal static class ColorUtil
{
    public static Vortice.Mathematics.Color4 ParseHex(string hex, float alpha = 1f)
    {
        var span = hex.AsSpan().Trim();
        if (span.StartsWith("#"))
        {
            span = span[1..];
        }

        if (span.Length == 6 &&
            byte.TryParse(span[..2], System.Globalization.NumberStyles.HexNumber, null, out var r) &&
            byte.TryParse(span[2..4], System.Globalization.NumberStyles.HexNumber, null, out var g) &&
            byte.TryParse(span[4..6], System.Globalization.NumberStyles.HexNumber, null, out var b))
        {
            return new Vortice.Mathematics.Color4(r / 255f, g / 255f, b / 255f, alpha);
        }

        return new Vortice.Mathematics.Color4(1, 1, 1, alpha);
    }
}
