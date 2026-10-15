using System.Runtime.InteropServices;

using Microsoft.Win32.SafeHandles;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WinMint.WinPeApply;

/// <summary>
/// Fullscreen black boot surface for the WinPE apply. The desktop itself is the black
/// <c>winpe.jpg</c> in the image; this window paints the mark and a progress row on that field.
/// </summary>
internal static class ApplyBootSplash
{
    internal static IDisposable TryShow()
    {
        BootSurface surface = new();
        if (!surface.Start())
        {
            surface.Dispose();
            return Nop.Instance;
        }

        return surface;
    }

    private sealed class Nop : IDisposable
    {
        internal static readonly Nop Instance = new();

        public void Dispose()
        {
        }
    }

    /// <summary>Owns the fullscreen window for the duration of LaunchApply.</summary>
    private sealed class BootSurface : IDisposable
    {
        private const uint WmClose = 0x0010;
        private const uint WmPaint = 0x000F;
        private const uint WmTick = 0x0400;

        private readonly ManualResetEventSlim _ready = new(false);
        private Thread? _uiThread;
        private SafeHwnd? _hwnd;
        private int _phase;
        private bool _shown;
        private bool _disposed;

        public bool Start()
        {
            _uiThread = new Thread(UiMain)
            {
                IsBackground = true,
                Name = "WinMint.BootSplash",
            };
            _uiThread.SetApartmentState(ApartmentState.STA);
            _uiThread.Start();
            _ = _ready.Wait(TimeSpan.FromSeconds(2));
            return _shown;
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            if (_hwnd is { IsInvalid: false } hwnd)
            {
                _ = PInvoke.PostMessage(hwnd.Hwnd, WmClose, default, default);
            }

            if (_uiThread is { IsAlive: true } ui)
            {
                _ = ui.Join(TimeSpan.FromSeconds(2));
            }

            _ready.Dispose();
        }

        private void UiMain()
        {
            try
            {
                EnsureWindow();
                HWND hwnd = _hwnd!.Hwnd;
                _ = PInvoke.ShowWindow(hwnd, SHOW_WINDOW_CMD.SW_SHOW);
                _ = PInvoke.UpdateWindow(hwnd);
                Paint(hwnd, beginPaint: false);
                using Timer tick = new(_ =>
                {
                    if (_hwnd is { IsInvalid: false } open)
                    {
                        _ = PInvoke.PostMessage(open.Hwnd, WmTick, default, default);
                    }
                }, null, 140, 140);
                _shown = true;
                _ready.Set();

                while (PInvoke.GetMessage(out MSG msg, HWND.Null, 0, 0))
                {
                    if (msg.message == WmPaint)
                    {
                        Paint(hwnd, beginPaint: true);
                        continue;
                    }

                    if (msg.message == WmTick)
                    {
                        _phase++;
                        Paint(hwnd, beginPaint: false);
                        continue;
                    }

                    if (msg.message == WmClose)
                    {
                        _hwnd?.Dispose();
                        _hwnd = null;
                        PInvoke.PostQuitMessage(0);
                        continue;
                    }

                    _ = PInvoke.TranslateMessage(msg);
                    _ = PInvoke.DispatchMessage(msg);
                }
            }
            catch (Exception)
            {
                _shown = false;
            }
            finally
            {
                _ready.Set();
            }
        }

        private void EnsureWindow()
        {
            int x = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_XVIRTUALSCREEN);
            int y = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_YVIRTUALSCREEN);
            int width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXVIRTUALSCREEN);
            int height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYVIRTUALSCREEN);
            if (width <= 0 || height <= 0)
            {
                x = 0;
                y = 0;
                width = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN);
                height = PInvoke.GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN);
            }

            if (width <= 0)
            {
                width = 800;
            }

            if (height <= 0)
            {
                height = 600;
            }

            FreeLibrarySafeHandle module = PInvoke.GetModuleHandle((string?)null);
            try
            {
                HWND created;
                unsafe
                {
                    created = PInvoke.CreateWindowEx(
                        WINDOW_EX_STYLE.WS_EX_TOPMOST | WINDOW_EX_STYLE.WS_EX_TOOLWINDOW,
                        "STATIC",
                        "WinMint",
                        WINDOW_STYLE.WS_POPUP | WINDOW_STYLE.WS_VISIBLE,
                        x,
                        y,
                        width,
                        height,
                        HWND.Null,
                        null,
                        module,
                        null);
                }

                if (created.IsNull)
                {
                    throw new InvalidOperationException($"CreateWindowExW failed: {Marshal.GetLastPInvokeError()}");
                }

                _hwnd = new SafeHwnd(created);
            }
            finally
            {
                module.SetHandleAsInvalid();
                module.Dispose();
            }
        }

        private void Paint(HWND hwnd, bool beginPaint)
        {
            PAINTSTRUCT paint = default;
            HDC hdc = beginPaint ? PInvoke.BeginPaint(hwnd, out paint) : PInvoke.GetDC(hwnd);
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

                HBRUSH black = PInvoke.CreateSolidBrush(new COLORREF(0));
                HGDIOBJ previous = PInvoke.SelectObject(hdc, black);
                _ = PInvoke.PatBlt(
                    hdc,
                    rect.left,
                    rect.top,
                    rect.right - rect.left,
                    rect.bottom - rect.top,
                    ROP_CODE.PATCOPY);
                _ = PInvoke.SelectObject(hdc, previous);
                _ = PInvoke.DeleteObject(black);

                int cx = (rect.left + rect.right) / 2;
                int cy = (rect.top + rect.bottom) / 2;
                DrawMark(hdc, cx, cy - 28);
                DrawProgress(hdc, cx, cy + 78);
            }
            finally
            {
                if (beginPaint)
                {
                    _ = PInvoke.EndPaint(hwnd, paint);
                }
                else
                {
                    _ = PInvoke.ReleaseDC(hwnd, hdc);
                }
            }
        }

        private static void DrawMark(HDC hdc, int cx, int cy)
        {
            const int size = 120;
            int x0 = cx - (size / 2);
            int y0 = cy - (size / 2);
            HGDIOBJ oldPen = PInvoke.SelectObject(hdc, PInvoke.GetStockObject(GET_STOCK_OBJECT_FLAGS.NULL_PEN));
            FillRound(hdc, x0 + 6, y0 + 22, x0 + 58, y0 + 112, 36, new COLORREF(0x00F27011));
            FillEllipse(hdc, x0 + 40, y0 + 4, x0 + 114, y0 + 62, new COLORREF(0x008CD04C));
            FillRound(hdc, x0 + 52, y0 + 56, x0 + 112, y0 + 114, 28, new COLORREF(0x00843900));
            _ = PInvoke.SelectObject(hdc, oldPen);
        }

        private void DrawProgress(HDC hdc, int cx, int cy)
        {
            const int count = 5;
            const int radius = 4;
            const int gap = 18;
            int lit = _phase % count;
            int origin = cx - (((count - 1) * gap) / 2);
            for (int i = 0; i < count; i++)
            {
                COLORREF color = i == lit ? new COLORREF(0x00FFFFFF) : new COLORREF(0x005C5C5C);
                int x = origin + (i * gap);
                FillEllipse(hdc, x - radius, cy - radius, x + radius, cy + radius, color);
            }
        }

        private static void FillRound(HDC hdc, int left, int top, int right, int bottom, int radius, COLORREF color)
        {
            HBRUSH brush = PInvoke.CreateSolidBrush(color);
            HGDIOBJ old = PInvoke.SelectObject(hdc, brush);
            _ = PInvoke.RoundRect(hdc, left, top, right, bottom, radius, radius);
            _ = PInvoke.SelectObject(hdc, old);
            _ = PInvoke.DeleteObject(brush);
        }

        private static void FillEllipse(HDC hdc, int left, int top, int right, int bottom, COLORREF color)
        {
            HBRUSH brush = PInvoke.CreateSolidBrush(color);
            HGDIOBJ old = PInvoke.SelectObject(hdc, brush);
            _ = PInvoke.Ellipse(hdc, left, top, right, bottom);
            _ = PInvoke.SelectObject(hdc, old);
            _ = PInvoke.DeleteObject(brush);
        }

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
}
