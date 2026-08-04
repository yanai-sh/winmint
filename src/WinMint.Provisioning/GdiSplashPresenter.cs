using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace WinMint.Provisioning;

/// <summary>
/// In-process opaque splash frame via GDI (full ID2D1Factory path only if S4 FirstPaintBudget still fails after status TextOutW).
/// Status is held in-memory; pixels are not a control plane.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed partial class GdiSplashPresenter : ISplashPresenter, IDisposable
{
    // ponytail: solid fill + status TextOutW for first opaque frame; full D2D only if S4 FirstPaintBudget still fails
    private const uint FillColorRef = 0x00281810; // BGR: 16,24,40

    private IntPtr _hwnd;
    private SessionStatus _status = new("shell.idle", "");
    private bool _shown;

    /// <summary>Last status pushed by the session (in-memory; not a file mailbox).</summary>
    public SessionStatus CurrentStatus => _status;

    public void Show()
    {
        if (_shown)
        {
            return;
        }

        EnsureWindow();
        if (!ShowWindow(_hwnd, SW_SHOW))
        {
            // ShowWindow returns false when already visible; still paint.
        }

        if (!UpdateWindow(_hwnd))
        {
            throw new InvalidOperationException($"UpdateWindow failed: {Marshal.GetLastPInvokeError()}");
        }

        PaintOpaque(_hwnd);
        _shown = true;
    }

    public void SetStatus(SessionStatus status)
    {
        _status = status;
        if (_hwnd != IntPtr.Zero)
        {
            PaintOpaque(_hwnd);
        }
    }

    public void Dispose()
    {
        if (_hwnd != IntPtr.Zero)
        {
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
    }

    private void EnsureWindow()
    {
        if (_hwnd != IntPtr.Zero)
        {
            return;
        }

        int width = GetSystemMetrics(SM_CXSCREEN);
        int height = GetSystemMetrics(SM_CYSCREEN);
        if (width <= 0)
        {
            width = 800;
        }

        if (height <= 0)
        {
            height = 600;
        }

        _hwnd = CreateWindowExW(
            WS_EX_TOPMOST,
            "STATIC",
            "WinMint",
            WS_POPUP | WS_VISIBLE,
            0,
            0,
            width,
            height,
            IntPtr.Zero,
            IntPtr.Zero,
            GetModuleHandleW(null),
            IntPtr.Zero);

        if (_hwnd == IntPtr.Zero)
        {
            throw new InvalidOperationException($"CreateWindowExW failed: {Marshal.GetLastPInvokeError()}");
        }

        PaintOpaque(_hwnd);
    }

    private void PaintOpaque(IntPtr hwnd)
    {
        IntPtr hdc = GetDC(hwnd);
        if (hdc == IntPtr.Zero)
        {
            return;
        }

        try
        {
            if (!GetClientRect(hwnd, out RECT rect))
            {
                return;
            }

            IntPtr brush = CreateSolidBrush(FillColorRef);
            if (brush == IntPtr.Zero)
            {
                return;
            }

            try
            {
                if (FillRect(hdc, ref rect, brush) == 0)
                {
                    throw new InvalidOperationException($"FillRect failed: {Marshal.GetLastPInvokeError()}");
                }
            }
            finally
            {
                if (!DeleteObject(brush))
                {
                    // best-effort cleanup
                }
            }

            DrawStatusText(hdc, rect);
        }
        finally
        {
            if (ReleaseDC(hwnd, hdc) != 1)
            {
                // best-effort cleanup
            }
        }
    }

    private void DrawStatusText(IntPtr hdc, RECT rect)
    {
        string label = string.IsNullOrWhiteSpace(_status.Message) ? _status.Code : _status.Message;
        if (string.IsNullOrWhiteSpace(label))
        {
            return;
        }

        IntPtr font = GetStockObject(StockGuiFont);
        if (font == IntPtr.Zero)
        {
            return;
        }

        IntPtr oldFont = SelectObject(hdc, font);
        try
        {
            if (SetBkMode(hdc, BkModeTransparent) == 0)
            {
                return;
            }

            if (SetTextColor(hdc, 0x00FFFFFF) == 0xFFFFFFFF)
            {
                return;
            }

            TextOutW(hdc, 48, 48, label, label.Length);
        }
        finally
        {
            if (oldFont != IntPtr.Zero)
            {
                SelectObject(hdc, oldFont);
            }
        }
    }

    private const int BkModeTransparent = 1;
    private const int StockGuiFont = 17;

    private const int SW_SHOW = 5;
    private const int SM_CXSCREEN = 0;
    private const int SM_CYSCREEN = 1;
    private const int WS_POPUP = unchecked((int)0x80000000);
    private const int WS_VISIBLE = 0x10000000;
    private const int WS_EX_TOPMOST = 0x00000008;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial IntPtr CreateWindowExW(
        int dwExStyle,
        [MarshalAs(UnmanagedType.LPWStr)] string lpClassName,
        [MarshalAs(UnmanagedType.LPWStr)] string lpWindowName,
        int dwStyle,
        int x,
        int y,
        int nWidth,
        int nHeight,
        IntPtr hWndParent,
        IntPtr hMenu,
        IntPtr hInstance,
        IntPtr lpParam);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DestroyWindow(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UpdateWindow(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    private static partial int GetSystemMetrics(int nIndex);

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetDC(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    private static partial int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [LibraryImport("user32.dll")]
    private static partial int FillRect(IntPtr hDC, ref RECT lprc, IntPtr hbr);

    [LibraryImport("gdi32.dll")]
    private static partial IntPtr CreateSolidBrush(uint crColor);

    [LibraryImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeleteObject(IntPtr ho);

    [LibraryImport("gdi32.dll")]
    private static partial int SetBkMode(IntPtr hdc, int mode);

    [LibraryImport("gdi32.dll")]
    private static partial uint SetTextColor(IntPtr hdc, uint color);

    [LibraryImport("gdi32.dll")]
    private static partial IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [LibraryImport("gdi32.dll")]
    private static partial IntPtr GetStockObject(int i);

    [LibraryImport("gdi32.dll", StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool TextOutW(IntPtr hdc, int x, int y, string lpString, int c);

    [LibraryImport("kernel32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr GetModuleHandleW(string? lpModuleName);
}
