using System;
using System.Runtime.InteropServices;

public static class WinMintNative {
    // Bump when adding/removing members so stale cached DLLs are not loaded.
    public const int CacheVersion = 8;

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS { public int Left, Right, Top, Bottom; }
    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);

    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hwnd, int nCmdShow);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags);

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT  { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT {
        public int length, flags, showCmd;
        public POINT ptMinPosition, ptMaxPosition;
        public RECT  rcNormalPosition;
    }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

    public static string GetWindowPosition(IntPtr hwnd) {
        var wp = new WINDOWPLACEMENT(); wp.length = Marshal.SizeOf(wp);
        if (!GetWindowPlacement(hwnd, ref wp)) return null;
        var r = wp.rcNormalPosition;
        return string.Format("{0},{1},{2},{3}", r.Left, r.Top, r.Right, r.Bottom);
    }

    public static void SetWindowPosition(IntPtr hwnd, int left, int top, int right, int bottom) {
        var wp = new WINDOWPLACEMENT();
        wp.length = Marshal.SizeOf(wp); wp.showCmd = 1;
        wp.rcNormalPosition = new RECT { Left = left, Top = top, Right = right, Bottom = bottom };
        SetWindowPlacement(hwnd, ref wp);
    }

    public static void EnableMica(IntPtr hwnd, bool darkMode) {
        int dark = darkMode ? 1 : 0;
        DwmSetWindowAttribute(hwnd, 20, ref dark, 4);
        int mica = 2;
        DwmSetWindowAttribute(hwnd, 38, ref mica, 4);
    }
    public static void DisableMica(IntPtr hwnd) {
        int none = 1; DwmSetWindowAttribute(hwnd, 38, ref none, 4);
    }
    public static void EnableShadow(IntPtr hwnd) {
        var m = new MARGINS { Left = 1, Right = 1, Top = 1, Bottom = 1 };
        DwmExtendFrameIntoClientArea(hwnd, ref m);
    }
    public static void EnableRoundedCorners(IntPtr hwnd) {
        int round = 2; DwmSetWindowAttribute(hwnd, 33, ref round, 4);
    }
}
