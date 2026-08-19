using System.Runtime.InteropServices;
using System.Runtime.Versioning;

using Microsoft.Win32.SafeHandles;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WinMint.Provisioning;

/// <summary>
/// In-process opaque splash frame via GDI (full ID2D1Factory path only if first opaque frame still fails after status TextOutW).
/// Status is held in-memory; pixels are not a control plane.
/// </summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class GdiSplashPresenter : ISplashPresenter, IDisposable
{
    // ponytail: solid fill + status TextOutW for first opaque frame; full D2D only if that path still fails
    private static readonly COLORREF FillColor = new(0x00281810); // BGR: 16,24,40

    private SafeHwnd? _hwnd;
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
        HWND hwnd = _hwnd!.Hwnd;
        _ = PInvoke.ShowWindow(hwnd, SHOW_WINDOW_CMD.SW_SHOW);

        if (!PInvoke.UpdateWindow(hwnd))
        {
            throw new InvalidOperationException($"UpdateWindow failed: {Marshal.GetLastPInvokeError()}");
        }

        PaintOpaque(hwnd);
        _shown = true;
    }

    public void SetStatus(SessionStatus status)
    {
        _status = status;
        if (_hwnd is { IsInvalid: false })
        {
            PaintOpaque(_hwnd.Hwnd);
        }
    }

    public void Dispose()
    {
        _hwnd?.Dispose();
        _hwnd = null;
    }

    private void EnsureWindow()
    {
        if (_hwnd is { IsInvalid: false })
        {
            return;
        }

        int width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
        int height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
        if (width <= 0)
        {
            width = 800;
        }

        if (height <= 0)
        {
            height = 600;
        }

        // GetModuleHandle does not bump the module refcount — FreeLibrarySafeHandle must not FreeLibrary it.
        // https://learn.microsoft.com/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulehandlew
        FreeLibrarySafeHandle module = PInvoke.GetModuleHandle((string?)null);
        try
        {
            HWND created = PInvoke.CreateWindowEx(
                WINDOW_EX_STYLE.WS_EX_TOPMOST,
                "STATIC",
                "WinMint",
                WINDOW_STYLE.WS_POPUP | WINDOW_STYLE.WS_VISIBLE,
                0,
                0,
                width,
                height,
                HWND.Null,
                null,
                module,
                null);

            if (created.IsNull)
            {
                throw new InvalidOperationException($"CreateWindowExW failed: {Marshal.GetLastPInvokeError()}");
            }

            _hwnd = new SafeHwnd(created);
            PaintOpaque(created);
        }
        finally
        {
            module.SetHandleAsInvalid();
            module.Dispose();
        }
    }

    private void PaintOpaque(HWND hwnd)
    {
        HDC hdc = PInvoke.GetDC(hwnd);
        if (hdc.IsNull)
        {
            return;
        }

        try
        {
            if (!PInvoke.GetClientRect(hwnd, out RECT rect))
            {
                return;
            }

            using DeleteObjectSafeHandle brush = PInvoke.CreateSolidBrush_SafeHandle(FillColor);
            if (brush.IsInvalid)
            {
                return;
            }

            if (PInvoke.FillRect(hdc, in rect, brush) == 0)
            {
                throw new InvalidOperationException($"FillRect failed: {Marshal.GetLastPInvokeError()}");
            }

            DrawStatusText(hdc);
        }
        finally
        {
            _ = PInvoke.ReleaseDC(hwnd, hdc);
        }
    }

    private void DrawStatusText(HDC hdc)
    {
        string label = string.IsNullOrWhiteSpace(_status.Message) ? _status.Code : _status.Message;
        if (string.IsNullOrWhiteSpace(label))
        {
            return;
        }

        HGDIOBJ font = PInvoke.GetStockObject(GET_STOCK_OBJECT_FLAGS.DEFAULT_GUI_FONT);
        if (font.IsNull)
        {
            return;
        }

        HGDIOBJ oldFont = PInvoke.SelectObject(hdc, font);
        try
        {
            if (PInvoke.SetBkMode(hdc, BACKGROUND_MODE.TRANSPARENT) == 0)
            {
                return;
            }

            if (PInvoke.SetTextColor(hdc, new COLORREF(0x00FFFFFF)) == new COLORREF(0xFFFFFFFF))
            {
                return;
            }

            _ = PInvoke.TextOut(hdc, 48, 48, label, label.Length);
        }
        finally
        {
            if (!oldFont.IsNull)
            {
                _ = PInvoke.SelectObject(hdc, oldFont);
            }
        }
    }

    /// <summary>Owns an HWND; <see cref="ReleaseHandle"/> calls DestroyWindow.</summary>
    private sealed class SafeHwnd : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeHwnd(HWND hwnd)
            : base(ownsHandle: true)
        {
            SetHandle(hwnd);
        }

        public HWND Hwnd => (HWND)handle;

        protected override bool ReleaseHandle() => PInvoke.DestroyWindow((HWND)handle);
    }
}
