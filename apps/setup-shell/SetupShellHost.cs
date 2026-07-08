using System.Runtime.InteropServices;
using System.Text.Json;
using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using Vortice.WIC;

namespace WinMintSetupShell;

internal sealed class SetupShellHost : IDisposable
{
    private readonly AppOptions _options;
    private readonly ShellLogger _logger;
    private readonly DesignTokens _tokens;
    private readonly nint _hwnd;
    private readonly WndProcDelegate _wndProc;
    private readonly GCHandle _selfHandle;

    private ID2D1Factory? _d2dFactory;
    private IDWriteFactory? _dwFactory;
    private ID2D1HwndRenderTarget? _renderTarget;
    private IDWriteTextFormat? _groupFormat;
    private IDWriteTextFormat? _taskFormat;
    private IDWriteTextFormat? _stepFormat;
    private IDWriteTextFormat? _bannerFormat;
    private HeroAsset? _heroAsset;

    private SetupShellStatus _status = new();
    private SetupShellControl _control = new();
    private DateTimeOffset? _firstPaintAt;
    private DateTimeOffset? _terminalPhaseAt;
    private bool _disposed;
    private bool _guestCaptureWritten;
    private bool _renderResourcesReady;
    private int _lastClientWidth;
    private int _lastClientHeight;
    private nint _backgroundBrush;
    private readonly SecondaryMonitorCover _secondaryCovers;
    private bool _useGdiFallback;
    private bool _gdiFallbackLogged;
    private int _consecutiveD2dFailures;
    private bool _framePaintLogged;

    private readonly string _guestCapturePath;
    private const int D2dFailureThreshold = 3;
    private const int HResultDxgiNotCurrentlyAvailable = unchecked((int)0x887A0022);
    private const int HResultD2dRecreateTarget = unchecked((int)0x8899000C);

    public SetupShellHost(AppOptions options, ShellLogger logger, DesignTokens tokens)
    {
        _options = options;
        _logger = logger;
        _tokens = tokens;
        _guestCapturePath = options.GuestCapturePath;
        _wndProc = WindowProc;
        _selfHandle = GCHandle.Alloc(this);

        // ponytail: opaque fallback when D2D is not ready yet (VMConnect before display metrics settle).
        _backgroundBrush = NativeMethods.CreateSolidBrush(0x001D1611);

        var wc = new NativeMethods.WNDCLASSEXW
        {
            Size = (uint)Marshal.SizeOf<NativeMethods.WNDCLASSEXW>(),
            Style = 0,
            WndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            Instance = NativeMethods.GetModuleHandle(null),
            ClassName = "WinMintSetupShellWindow",
            Cursor = NativeMethods.LoadCursor(nint.Zero, NativeMethods.IDC_ARROW),
            Background = _backgroundBrush
        };
        NativeMethods.RegisterClassExW(ref wc);

        var bounds = MonitorUtil.GetPrimaryMonitorBounds();
        _hwnd = NativeMethods.CreateWindowExW(
            NativeMethods.WS_EX_TOPMOST,
            wc.ClassName,
            "WinMint Setup",
            NativeMethods.WS_POPUP | NativeMethods.WS_VISIBLE,
            bounds.Left, bounds.Top, bounds.Width, bounds.Height,
            nint.Zero, nint.Zero, wc.Instance, nint.Zero);

        if (_hwnd == nint.Zero)
        {
            throw new InvalidOperationException("Failed to create setup shell window.");
        }

        MonitorUtil.ApplyFullscreenBounds(_hwnd, bounds);
        NativeMethods.ShowWindow(_hwnd, NativeMethods.SW_SHOW);

        _secondaryCovers = new SecondaryMonitorCover();
        _secondaryCovers.Sync();
        if (_secondaryCovers.CoverCount > 0)
        {
            _logger.Info($"secondary monitor blanks={_secondaryCovers.CoverCount}");
        }

        PollJson(forceLog: true);
        NativeMethods.SetTimer(_hwnd, NativeMethods.TIMER_ID, (uint)_options.PollMs, nint.Zero);
    }

    public int Run()
    {
        if (!_options.Preview)
        {
            DesktopGuard.Tick(_hwnd, _secondaryCovers);
        }
        while (NativeMethods.GetMessageW(out var msg, nint.Zero, 0, 0))
        {
            NativeMethods.TranslateMessage(ref msg);
            NativeMethods.DispatchMessageW(ref msg);
        }

        return 0;
    }

    private nint WindowProc(nint hWnd, uint msg, nuint wParam, nint lParam)
    {
        switch (msg)
        {
            case NativeMethods.WM_TIMER:
                OnTimer();
                return 0;
            case NativeMethods.WM_PAINT:
                NativeMethods.BeginPaint(hWnd, out var paint);
                try
                {
                    RenderFrame(paint.Hdc);
                }
                finally
                {
                    NativeMethods.EndPaint(hWnd, ref paint);
                }
                return 0;
            case NativeMethods.WM_ACTIVATE:
                OnDisplayMetricsChanged(hWnd);
                return 0;
            case NativeMethods.WM_DISPLAYCHANGE:
                _secondaryCovers.Sync();
                OnDisplayMetricsChanged(hWnd);
                return 0;
            case NativeMethods.WM_DPICHANGED:
                var suggested = Marshal.PtrToStructure<NativeMethods.RECT>(lParam);
                MonitorUtil.ApplyFullscreenBounds(hWnd, suggested);
                _secondaryCovers.Sync();
                OnDisplayMetricsChanged(hWnd);
                return 0;
            case NativeMethods.WM_KEYDOWN when _options.Preview && wParam == NativeMethods.VK_ESCAPE:
                NativeMethods.DestroyWindow(hWnd);
                return 0;
            case NativeMethods.WM_DESTROY:
                NativeMethods.KillTimer(hWnd, NativeMethods.TIMER_ID);
                NativeMethods.PostQuitMessage(0);
                return 0;
        }

        return NativeMethods.DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void OnTimer()
    {
        OnDisplayMetricsChanged(_hwnd);
        PollJson(forceLog: false);
        NativeMethods.InvalidateRect(_hwnd, nint.Zero, false);

        if (ShouldClose())
        {
            NativeMethods.DestroyWindow(_hwnd);
        }
    }

    private void OnDisplayMetricsChanged(nint hWnd)
    {
        if (!_options.Preview)
        {
            DesktopGuard.Tick(hWnd, _secondaryCovers);
        }
        else
        {
            MonitorUtil.ApplyFullscreenBounds(hWnd, MonitorUtil.GetPrimaryMonitorBounds());
        }
        NativeMethods.GetClientRect(hWnd, out var rect);
        if (rect.Width <= 0 || rect.Height <= 0)
        {
            return;
        }

        if (rect.Width != _lastClientWidth || rect.Height != _lastClientHeight)
        {
            _lastClientWidth = rect.Width;
            _lastClientHeight = rect.Height;
            if (_renderTarget is not null)
            {
                RecreateRenderTarget();
            }
        }
    }

    private void PollJson(bool forceLog)
    {
        if (!TryReadRuntimeState())
        {
            _ = TryReadJson(_options.StatusPath, ref _status);
            _ = TryReadControl(_options.ControlPath, ref _control);
        }
    }

    private bool TryReadRuntimeState()
    {
        try
        {
            var path = _options.RuntimeStatePath;
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            {
                return false;
            }

            var json = File.ReadAllText(path);
            var parsed = JsonSerializer.Deserialize(json, SetupShellJsonContext.Default.RuntimeStateDocument);
            if (parsed is null)
            {
                return false;
            }

            var read = false;
            if (parsed.Display is not null)
            {
                _status = parsed.Display;
                read = true;
            }
            if (parsed.Control is not null)
            {
                _control = parsed.Control;
                read = true;
            }

            return read;
        }
        catch (Exception ex)
        {
            _logger.Info($"runtime-state read warning: {ex.Message}");
            return false;
        }
    }

    private bool TryReadJson(string path, ref SetupShellStatus target)
    {
        try
        {
            if (!File.Exists(path))
            {
                return false;
            }

            var json = File.ReadAllText(path);
            var parsed = JsonSerializer.Deserialize(json, SetupShellJsonContext.Default.SetupShellStatus);
            if (parsed is null)
            {
                _logger.Info($"status parse warning: empty payload from {path}");
                return false;
            }

            target = parsed;
            return true;
        }
        catch (Exception ex)
        {
            _logger.Info($"status read warning: {ex.Message}");
            return false;
        }
    }

    private bool TryReadControl(string path, ref SetupShellControl target)
    {
        try
        {
            if (!File.Exists(path))
            {
                return false;
            }

            var json = File.ReadAllText(path);
            var parsed = JsonSerializer.Deserialize(json, SetupShellJsonContext.Default.SetupShellControl);
            if (parsed is null)
            {
                return false;
            }

            target = parsed;
            return true;
        }
        catch (Exception ex)
        {
            _logger.Info($"control read warning: {ex.Message}");
            return false;
        }
    }

    private bool ShouldClose()
    {
        var phase = _control.Phase;
        if (phase is not ("complete" or "failed" or "reboot"))
        {
            _terminalPhaseAt = null;
            return false;
        }

        // ponytail: dwell starts after a visible frame (D2D or GDI); GDI engages after D2dFailureThreshold misses
        if (_firstPaintAt is null)
        {
            return false;
        }

        var now = DateTimeOffset.Now;
        if ((now - _firstPaintAt.Value).TotalMilliseconds < _options.MinStartDwellMs)
        {
            return false;
        }

        _terminalPhaseAt ??= now;
        return (now - _terminalPhaseAt.Value).TotalMilliseconds >= _options.MinCompleteDwellMs;
    }

    private void MarkFirstPaint()
    {
        if (_firstPaintAt is not null)
        {
            return;
        }

        _firstPaintAt = DateTimeOffset.Now;
        if (!_framePaintLogged)
        {
            _framePaintLogged = true;
            _logger.Info("presenter=frame-painted");
        }
    }

    private void EngageGdiFallback()
    {
        if (_useGdiFallback)
        {
            return;
        }

        _useGdiFallback = true;
        if (!_gdiFallbackLogged)
        {
            _gdiFallbackLogged = true;
            _logger.Info("presenter=gdi-fallback");
        }
    }

    private bool EnsureRenderResources()
    {
        if (_renderResourcesReady && _renderTarget is not null)
        {
            return true;
        }

        try
        {
            InitRenderResources();
            if (_renderTarget is null)
            {
                return false;
            }

            _heroAsset = SplashPainter.LoadHeroBitmap(_renderTarget, _options.ShellRoot, _logger);
            _renderResourcesReady = true;
            if (_renderTarget is not null)
            {
                NativeMethods.GetClientRect(_hwnd, out var rect);
                _logger.Info($"render ready {rect.Width}x{rect.Height}");
            }
            return _renderTarget is not null;
        }
        catch (Exception ex)
        {
            _logger.Info($"render init warning: {ex.Message}");
            ReleaseRenderResources();
            return false;
        }
    }

    private void InitRenderResources()
    {
        _d2dFactory ??= D2D1.D2D1CreateFactory<ID2D1Factory>();
        _dwFactory ??= DWrite.DWriteCreateFactory<IDWriteFactory>();
        ResizeRenderTarget();

        NativeMethods.GetClientRect(_hwnd, out var client);
        var metrics = SplashLayout.Resolve(
            Math.Max(1, client.Width),
            Math.Max(1, client.Height),
            _tokens.Layout);
        var fontCollection = _dwFactory.GetSystemFontCollection(false);

        _groupFormat = _dwFactory.CreateTextFormat(
            _tokens.FontFamily,
            fontCollection,
            FontWeight.SemiBold,
            FontStyle.Normal,
            FontStretch.Normal,
            metrics.GroupFontSize);
        _groupFormat.TextAlignment = TextAlignment.Leading;
        _groupFormat.ParagraphAlignment = ParagraphAlignment.Near;

        _taskFormat = _dwFactory.CreateTextFormat(
            _tokens.FontFamily,
            fontCollection,
            FontWeight.Medium,
            FontStyle.Normal,
            FontStretch.Normal,
            metrics.TaskFontSize);
        _taskFormat.TextAlignment = TextAlignment.Leading;
        _taskFormat.ParagraphAlignment = ParagraphAlignment.Near;
        _taskFormat.WordWrapping = WordWrapping.Wrap;

        _stepFormat = _dwFactory.CreateTextFormat(
            _tokens.FontFamily,
            fontCollection,
            FontWeight.Normal,
            FontStyle.Normal,
            FontStretch.Normal,
            metrics.StepFontSize);
        _stepFormat.TextAlignment = TextAlignment.Leading;
        _stepFormat.ParagraphAlignment = ParagraphAlignment.Near;

        _bannerFormat = _dwFactory.CreateTextFormat(
            _tokens.FontFamily,
            fontCollection,
            FontWeight.Normal,
            FontStyle.Normal,
            FontStretch.Normal,
            13f);
        _bannerFormat.TextAlignment = TextAlignment.Center;
        _bannerFormat.ParagraphAlignment = ParagraphAlignment.Center;
        _bannerFormat.WordWrapping = WordWrapping.Wrap;
    }

    private void ResizeRenderTarget()
    {
        NativeMethods.GetClientRect(_hwnd, out var rect);
        var size = new SizeI(rect.Width, rect.Height);
        if (_renderTarget is null)
        {
            var hwndProps = new HwndRenderTargetProperties
            {
                Hwnd = _hwnd,
                PixelSize = size,
                PresentOptions = PresentOptions.None
            };
            try
            {
                _renderTarget = _d2dFactory!.CreateHwndRenderTarget(new RenderTargetProperties(), hwndProps);
            }
            catch (Exception ex) when (IsLostRenderTarget(ex))
            {
                _logger.Info($"hwnd render retry: {ex.Message}");
                Thread.Sleep(500);
                _renderTarget = _d2dFactory!.CreateHwndRenderTarget(new RenderTargetProperties(), hwndProps);
            }
            return;
        }

        if (rect.Width > 0 && rect.Height > 0)
        {
            _renderTarget.Resize(size);
        }
    }

    private void RenderFrame(nint hdc)
    {
        NativeMethods.GetClientRect(_hwnd, out var client);
        var width = client.Width;
        var height = client.Height;

        if (_useGdiFallback)
        {
            GdiFallbackPainter.Paint(hdc, width, height, _tokens, _status);
            MarkFirstPaint();
            if (_firstPaintAt is not null && !_guestCaptureWritten)
            {
                TryWriteGuestCapture();
            }
            return;
        }

        if (!TryRenderD2D(width, height))
        {
            _consecutiveD2dFailures++;
            if (_consecutiveD2dFailures >= D2dFailureThreshold)
            {
                EngageGdiFallback();
                if (hdc != nint.Zero)
                {
                    GdiFallbackPainter.Paint(hdc, width, height, _tokens, _status);
                    MarkFirstPaint();
                }
            }
        }
    }

    private bool TryRenderD2D(int width, int height)
    {
        if (!EnsureRenderResources() || _renderTarget is null || _groupFormat is null || _taskFormat is null || _stepFormat is null || _bannerFormat is null)
        {
            return false;
        }

        var captureThisFrame = _firstPaintAt is null;
        try
        {
            _renderTarget.BeginDraw();
        }
        catch (Exception ex) when (IsLostRenderTarget(ex))
        {
            _logger.Info($"begin draw warning: {ex.Message}");
            RecreateRenderTarget();
            return false;
        }

        SplashPainter.Paint(
            _renderTarget,
            width,
            height,
            _tokens,
            _status,
            _heroAsset,
            _groupFormat,
            _taskFormat,
            _stepFormat,
            _bannerFormat);

        try
        {
            _renderTarget.EndDraw();
        }
        catch (Exception ex) when (IsLostRenderTarget(ex))
        {
            _logger.Info($"end draw warning: {ex.Message}");
            RecreateRenderTarget();
            return false;
        }

        _consecutiveD2dFailures = 0;
        MarkFirstPaint();
        if (captureThisFrame)
        {
            TryWriteGuestCapture();
        }

        return true;
    }

    private static bool IsLostRenderTarget(Exception ex)
    {
        var hresult = ex.HResult;
        return hresult is HResultDxgiNotCurrentlyAvailable or HResultD2dRecreateTarget;
    }

    private void RecreateRenderTarget()
    {
        _heroAsset?.Dispose();
        _heroAsset = null;
        _renderTarget?.Dispose();
        _renderTarget = null;
        _renderResourcesReady = false;
        _ = EnsureRenderResources();
        NativeMethods.InvalidateRect(_hwnd, nint.Zero, false);
    }

    private void ReleaseRenderResources()
    {
        _heroAsset?.Dispose();
        _heroAsset = null;
        _groupFormat?.Dispose();
        _groupFormat = null;
        _taskFormat?.Dispose();
        _taskFormat = null;
        _stepFormat?.Dispose();
        _stepFormat = null;
        _bannerFormat?.Dispose();
        _bannerFormat = null;
        _renderTarget?.Dispose();
        _renderTarget = null;
        _dwFactory?.Dispose();
        _dwFactory = null;
        _d2dFactory?.Dispose();
        _d2dFactory = null;
        _renderResourcesReady = false;
    }

    private void TryWriteGuestCapture()
    {
        if (_guestCaptureWritten)
        {
            return;
        }

        if (GuestScreenCapture.TryCaptureWindow(_hwnd, _guestCapturePath))
        {
            _guestCaptureWritten = true;
            _logger.Info($"guest-capture={_guestCapturePath}");
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _secondaryCovers.Dispose();
        DesktopGuard.ClearNoWinKeys();
        DesktopGuard.ClearDisableTaskSwitching();
        DesktopGuard.DismissStartMenu();
        DesktopGuard.ShowTaskbars();
        if (_backgroundBrush != nint.Zero)
        {
            NativeMethods.DeleteObject(_backgroundBrush);
            _backgroundBrush = nint.Zero;
        }
        ReleaseRenderResources();
        if (_selfHandle.IsAllocated)
        {
            _selfHandle.Free();
        }
    }
}

internal delegate nint WndProcDelegate(nint hWnd, uint msg, nuint wParam, nint lParam);

internal static partial class NativeMethods
{
    public const int SM_CXSCREEN = 0;
    public const int SM_CYSCREEN = 1;
    public const nint IDC_ARROW = 32512;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern nint GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern nint LoadCursor(nint hInstance, nint lpCursorName);
}
