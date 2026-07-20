using System.Runtime.InteropServices;

namespace WinMintSetupShell;

/// <summary>
/// OS accessibility probes for the native splash: reduced motion, high contrast,
/// and Narrator-oriented name-change announcements (AOT-safe, no UIA provider).
/// </summary>
internal static class SystemAccessibility
{
    private const uint SpiGetClientAreaAnimation = 0x1042;
    private const uint SpiGetHighContrast = 0x0042;
    private const uint HcfHighContrastOn = 0x00000001;
    private const uint EventObjectNameChange = 0x800C;
    private const int ObjIdWindow = 0;
    private const int ChildIdSelf = 0;

    private const int ColorWindow = 5;
    private const int ColorWindowText = 8;
    private const int ColorGrayText = 17;
    private const int ColorHighlight = 13;
    private const int ColorBtnShadow = 16;
    private const int ColorBtnText = 18;

    public static bool ReduceMotion { get; private set; }
    public static bool HighContrast { get; private set; }

    public static void Refresh()
    {
        ReduceMotion = !QueryClientAreaAnimationEnabled();
        HighContrast = QueryHighContrastEnabled();
    }

    public static DesignTokens ResolvePaintTokens(DesignTokens baseline)
    {
        if (!HighContrast)
        {
            return baseline;
        }

        var window = ToHex(NativeMethods.GetSysColor(ColorWindow));
        var text = ToHex(NativeMethods.GetSysColor(ColorWindowText));
        var gray = ToHex(NativeMethods.GetSysColor(ColorGrayText));
        var highlight = ToHex(NativeMethods.GetSysColor(ColorHighlight));
        var shadow = ToHex(NativeMethods.GetSysColor(ColorBtnShadow));
        var btnText = ToHex(NativeMethods.GetSysColor(ColorBtnText));

        return new DesignTokens
        {
            Canvas = window,
            Ink = text,
            Muted = gray,
            Dim = gray,
            Accent = highlight,
            Warn = highlight,
            Fail = btnText,
            ProgressTrack = shadow,
            ProgressFill = text,
            FontFamily = baseline.FontFamily,
            Layout = baseline.Layout
        };
    }

    public static string BuildAnnouncement(SetupShellStatus status, bool stalled)
    {
        var overlay = SplashPainterOverlay.Resolve(status, stalled);
        var parts = new List<string>(4)
        {
            string.IsNullOrWhiteSpace(overlay.TaskLabel) ? "Getting things ready" : overlay.TaskLabel
        };
        if (!string.IsNullOrWhiteSpace(overlay.DetailLabel))
        {
            parts.Add(overlay.DetailLabel);
        }

        if (overlay.ItemTotal > 0 && !overlay.IsAlert && !overlay.IsTerminal)
        {
            parts.Add($"{Math.Max(1, overlay.ItemIndex)} of {overlay.ItemTotal}");
        }

        if (!string.IsNullOrWhiteSpace(overlay.RecoveryLine))
        {
            parts.Add(overlay.RecoveryLine.Replace('\n', ' '));
        }

        return string.Join(". ", parts);
    }

    public static void Announce(nint hwnd, string announcement)
    {
        if (hwnd == nint.Zero || string.IsNullOrWhiteSpace(announcement))
        {
            return;
        }

        var title = "WinMint Setup — " + announcement.Trim();
        if (title.Length > 240)
        {
            title = title[..239] + "…";
        }

        NativeMethods.SetWindowTextW(hwnd, title);
        NativeMethods.NotifyWinEvent(EventObjectNameChange, hwnd, ObjIdWindow, ChildIdSelf);
    }

    private static bool QueryClientAreaAnimationEnabled()
    {
        var enabled = 1;
        return NativeMethods.SystemParametersInfoW(SpiGetClientAreaAnimation, 0, ref enabled, 0)
            && enabled != 0;
    }

    private static bool QueryHighContrastEnabled()
    {
        var hc = new NativeMethods.HIGHCONTRASTW
        {
            Size = (uint)Marshal.SizeOf<NativeMethods.HIGHCONTRASTW>()
        };
        if (!NativeMethods.SystemParametersInfoHighContrast(SpiGetHighContrast, hc.Size, ref hc, 0))
        {
            return false;
        }

        return (hc.Flags & HcfHighContrastOn) != 0;
    }

    private static string ToHex(int colorRef)
    {
        var r = colorRef & 0xFF;
        var g = (colorRef >> 8) & 0xFF;
        var b = (colorRef >> 16) & 0xFF;
        return $"#{r:X2}{g:X2}{b:X2}";
    }
}
