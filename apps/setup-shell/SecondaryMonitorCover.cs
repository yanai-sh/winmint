using System.Runtime.InteropServices;

namespace WinMintSetupShell;

internal sealed class SecondaryMonitorCover : IDisposable
{
    private const uint MonitorInfoPrimary = 1;
    private const int WsExNoActivate = 0x08000000;

    private readonly List<CoverEntry> _covers = [];
    private readonly nint _blackBrush;
    private readonly nint _instance;
    private readonly NativeMethods.MonitorEnumProc _enumProc;
    private static readonly WndProcDelegate BlankWindowProc = BlankWndProc;
    private bool _classRegistered;
    private bool _disposed;

    private readonly struct CoverEntry
    {
        public nint Hwnd { get; init; }
        public NativeMethods.RECT Bounds { get; init; }
    }

    public SecondaryMonitorCover()
    {
        _blackBrush = NativeMethods.CreateSolidBrush(0);
        _instance = NativeMethods.GetModuleHandle(null);
        _enumProc = OnMonitorEnum;
    }

    public int CoverCount => _covers.Count;

    public void Sync()
    {
        if (_disposed)
        {
            return;
        }

        DestroyCovers();
        EnsureClass();

        var state = new EnumState();
        var handle = GCHandle.Alloc(state);
        try
        {
            NativeMethods.EnumDisplayMonitors(nint.Zero, nint.Zero, _enumProc, GCHandle.ToIntPtr(handle));
        }
        finally
        {
            handle.Free();
        }

        foreach (var bounds in state.Targets)
        {
            var hwnd = NativeMethods.CreateWindowExW(
                NativeMethods.WS_EX_TOPMOST | WsExNoActivate,
                "WinMintSetupShellBlank",
                string.Empty,
                NativeMethods.WS_POPUP | NativeMethods.WS_VISIBLE,
                bounds.Left,
                bounds.Top,
                bounds.Width,
                bounds.Height,
                nint.Zero,
                nint.Zero,
                _instance,
                nint.Zero);
            if (hwnd == nint.Zero)
            {
                continue;
            }

            MonitorUtil.ApplyFullscreenBounds(hwnd, bounds);
            _covers.Add(new CoverEntry { Hwnd = hwnd, Bounds = bounds });
        }
    }

    public void ApplyBounds()
    {
        foreach (var cover in _covers)
        {
            MonitorUtil.ApplyFullscreenBounds(cover.Hwnd, cover.Bounds);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        DestroyCovers();
        if (_blackBrush != nint.Zero)
        {
            NativeMethods.DeleteObject(_blackBrush);
        }
    }

    private void EnsureClass()
    {
        if (_classRegistered)
        {
            return;
        }

        var wc = new NativeMethods.WNDCLASSEXW
        {
            Size = (uint)Marshal.SizeOf<NativeMethods.WNDCLASSEXW>(),
            Style = 0,
            WndProc = Marshal.GetFunctionPointerForDelegate(BlankWindowProc),
            Instance = _instance,
            ClassName = "WinMintSetupShellBlank",
            Background = _blackBrush
        };
        NativeMethods.RegisterClassExW(ref wc);
        _classRegistered = true;
    }

    private static nint BlankWndProc(nint hWnd, uint msg, nuint wParam, nint lParam) =>
        NativeMethods.DefWindowProcW(hWnd, msg, wParam, lParam);

    private bool OnMonitorEnum(nint hMonitor, nint hdcMonitor, ref NativeMethods.RECT lprcMonitor, nint dwData)
    {
        var state = (EnumState)GCHandle.FromIntPtr(dwData).Target!;
        var info = new NativeMethods.MONITORINFO
        {
            Size = Marshal.SizeOf<NativeMethods.MONITORINFO>()
        };
        if (!NativeMethods.GetMonitorInfoW(hMonitor, ref info))
        {
            return true;
        }

        if ((info.Flags & MonitorInfoPrimary) != 0)
        {
            return true;
        }

        state.Targets.Add(info.Monitor);
        return true;
    }

    private void DestroyCovers()
    {
        foreach (var cover in _covers)
        {
            if (cover.Hwnd != nint.Zero)
            {
                NativeMethods.DestroyWindow(cover.Hwnd);
            }
        }

        _covers.Clear();
    }

    private sealed class EnumState
    {
        public List<NativeMethods.RECT> Targets { get; } = [];
    }
}
