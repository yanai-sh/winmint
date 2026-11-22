using System.Runtime.InteropServices;

using Microsoft.Win32.SafeHandles;

using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.Graphics.Gdi;
using Windows.Win32.UI.HiDpi;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WinMint.WinPeApply;

/// <summary>
/// Fullscreen black boot surface for the WinPE apply. The desktop itself is the black
/// <c>winpe.jpg</c> in the image; this window paints the dark lockup and a progress row on that field.
/// </summary>
internal static class ApplyBootSplash
{
    internal const string EscapeVariable = "WINMINT_SPLASH_ESCAPE";

    private static int s_escapeRequested;

    internal static bool EscapeRequested => Volatile.Read(ref s_escapeRequested) != 0;

    internal static void RequestEscape() => Interlocked.Exchange(ref s_escapeRequested, 1);

    internal static void EnablePerMonitorV2()
    {
        // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2. A second call fails once a context is set.
#pragma warning disable CA1416 // WinPE on a current Source ISO is Windows 10 or later.
        _ = PInvoke.SetProcessDpiAwarenessContext(new DPI_AWARENESS_CONTEXT((nint)(-4)));
#pragma warning restore CA1416
    }

    internal static IDisposable TryShow()
    {
        Interlocked.Exchange(ref s_escapeRequested, 0);
        BootSurface surface = new();
        if (!surface.Start())
        {
            surface.Dispose();
            return Nop.Instance;
        }

        return surface;
    }

    /// <summary>
    /// Host preview of the apply splash, plus the disk list under that lockup. Does not start LaunchApply.
    /// Esc closes the window. Choosing a disk does not change it.
    /// </summary>
    internal static void HoldForPreview()
    {
        IReadOnlyList<SplashDisk> disks;
        try
        {
            disks = SplashDiskList.Read(out _);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            disks = [];
        }

        BootSurface surface = new(escapeEnabled: true, disks);
        try
        {
            if (!surface.Start())
            {
                return;
            }

            surface.JoinUi();
        }
        finally
        {
            surface.Dispose();
        }
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
        private const uint WmLButtonDown = 0x0201;
        private const uint WmTick = 0x0400;

        private const int VkEscape = 0x1B;
        private const int VkReturn = 0x0D;
        private const int VkUp = 0x26;
        private const int VkDown = 0x28;

        private readonly bool _escapeEnabled;
        private readonly bool _picker;
        private readonly IReadOnlyList<SplashDisk> _disks;
        private readonly ManualResetEventSlim _ready = new(false);
        private Thread? _uiThread;
        private SafeHwnd? _hwnd;
        private SplashPromptPainter? _painter;
        private int _phase;
        private int _focus = -1;
        private int _marked = -1;
        private int _upHeld;
        private int _downHeld;
        private int _enterHeld;
        private int _dpi = 96;
        private bool _shown;
        private bool _disposed;

        internal BootSurface(bool? escapeEnabled = null)
            : this(escapeEnabled, disks: null)
        {
        }

        internal BootSurface(bool? escapeEnabled, IReadOnlyList<SplashDisk>? disks)
        {
            _escapeEnabled = escapeEnabled ?? string.Equals(
                Environment.GetEnvironmentVariable(EscapeVariable),
                "1",
                StringComparison.Ordinal);
            _picker = disks is not null;
            _disks = disks ?? [];
            _focus = _picker ? SplashDiskPrompt.InitialFocus(_disks.Count) : -1;
        }

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

        internal void JoinUi() => _uiThread?.Join();

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
                if (_picker)
                {
                    _ = PInvoke.SetForegroundWindow(hwnd);
                    _ = PInvoke.SetWindowText(hwnd, SplashDiskPrompt.Heading);
#pragma warning disable CA1416 // WinPE on a current Source ISO is Windows 10 or later.
                    uint dpi = PInvoke.GetDpiForWindow(hwnd);
#pragma warning restore CA1416
                    if (dpi > 0)
                    {
                        _dpi = (int)dpi;
                    }

                    _painter = new SplashPromptPainter();
                }

                Paint(hwnd, beginPaint: false);
                int tickMs = _picker ? 40 : 140;
                using Timer tick = new(_ =>
                {
                    if (_hwnd is { IsInvalid: false } open)
                    {
                        _ = PInvoke.PostMessage(open.Hwnd, WmTick, default, default);
                    }
                }, null, tickMs, tickMs);
                _shown = true;
                _ready.Set();
                DismissIfEscape();

                while (PInvoke.GetMessage(out MSG msg, HWND.Null, 0, 0))
                {
                    if (msg.message == WmPaint)
                    {
                        Paint(hwnd, beginPaint: true);
                        continue;
                    }

                    if (msg.message == WmTick)
                    {
                        if (_picker)
                        {
                            if (PollKeys())
                            {
                                Paint(hwnd, beginPaint: false);
                            }
                        }
                        else
                        {
                            _phase++;
                            Paint(hwnd, beginPaint: false);
                        }

                        DismissIfEscape();
                        continue;
                    }

                    if (_picker && msg.message == WmLButtonDown && msg.hwnd == hwnd && SelectAt(ClickX(msg.lParam), ClickY(msg.lParam)))
                    {
                        Paint(hwnd, beginPaint: false);
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
                _painter?.Dispose();
                _painter = null;
                _ready.Set();
            }
        }

        private bool PollKeys()
        {
            bool changed = false;
            changed |= Edge(VkUp, ref _upHeld, allowRepeat: true, () => Move(-1));
            changed |= Edge(VkDown, ref _downHeld, allowRepeat: true, () => Move(1));
            changed |= Edge(VkReturn, ref _enterHeld, allowRepeat: false, Confirm);
            return changed;
        }

        private static bool Edge(int vk, ref int held, bool allowRepeat, Func<bool> act)
        {
            bool down = (PInvoke.GetAsyncKeyState(vk) & 0x8000) != 0;
            if (!down)
            {
                held = 0;
                return false;
            }

            held++;
            bool fire = held == 1 || (allowRepeat && held >= 8 && (held - 8) % 3 == 0);
            return fire && act();
        }

        private bool SelectAt(int x, int y)
        {
            if (_painter is null)
            {
                return false;
            }

            int row = _painter.RowAt(x, y);
            if (row < 0 || row == _focus)
            {
                return false;
            }

            _focus = row;
            _marked = -1;
            return true;
        }

        private static int ClickX(LPARAM packed) => unchecked((short)(packed.Value & 0xFFFF));

        private static int ClickY(LPARAM packed) => unchecked((short)((packed.Value >> 16) & 0xFFFF));

        private bool Move(int direction)
        {
            if (_disks.Count == 0)
            {
                return false;
            }

            int next = _focus < 0
                ? (direction > 0 ? 0 : _disks.Count - 1)
                : Math.Clamp(_focus + direction, 0, _disks.Count - 1);
            if (next == _focus)
            {
                return false;
            }

            _focus = next;
            _marked = -1;
            return true;
        }

        private bool Confirm()
        {
            if (_focus < 0 || _focus >= _disks.Count || _marked == _focus)
            {
                return false;
            }

            _marked = _focus;
            return true;
        }

        private void DismissIfEscape()
        {
            if (!_escapeEnabled || EscapeRequested)
            {
                return;
            }

            if ((PInvoke.GetAsyncKeyState(VkEscape) & 0x8000) == 0)
            {
                return;
            }

            RequestEscape();
            if (_hwnd is { IsInvalid: false } hwnd)
            {
                _ = PInvoke.PostMessage(hwnd.Hwnd, WmClose, default, default);
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

                if (_picker && _painter is not null)
                {
                    _painter.Paint(hdc, rect, _dpi, _disks, _focus, _marked);
                    return;
                }

                int cx = (rect.left + rect.right) / 2;
                int cy = (rect.top + rect.bottom) / 2;
                if (BrandLockup.TryBlit(hdc, rect, out int bottom))
                {
                    int progressY = bottom + 36;
                    if (progressY > rect.bottom - 16)
                    {
                        progressY = rect.bottom - 16;
                    }

                    DrawProgress(hdc, cx, progressY);
                }
                else
                {
                    BrandMark.Draw(hdc, cx, cy - 28);
                    DrawProgress(hdc, cx, cy + 78);
                }
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
