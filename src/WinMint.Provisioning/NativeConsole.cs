using System.Runtime.Versioning;
using Windows.Win32;
using Windows.Win32.Foundation;
using Windows.Win32.UI.WindowsAndMessaging;

namespace WinMint.Provisioning;

/// <summary>Hide the SetupComplete console so OOBE does not look like a script.</summary>
[SupportedOSPlatform("windows10.0.19041.0")]
internal static class NativeConsole
{
    public static void Hide()
    {
        HWND hwnd = PInvoke.GetConsoleWindow();
        if (hwnd == HWND.Null)
        {
            return;
        }

        _ = PInvoke.ShowWindow(hwnd, SHOW_WINDOW_CMD.SW_HIDE);
    }
}
