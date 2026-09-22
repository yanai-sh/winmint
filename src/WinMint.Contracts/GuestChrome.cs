namespace WinMint.Contracts;

/// <summary>Guest paths and ISO-baked Start/taskbar chrome shared by Plan and FirstLogon.</summary>
public static class GuestChrome
{
    public const string BloomWallpaperPath = @"C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg";

    /// <summary>HKLM ConfigureStartPins baseline (Explorer, Settings, Terminal). Extra winget apps are taskbar XML only.</summary>
    public const string StartPinsBaselineJson =
        """{"pinnedList":[{"desktopAppId":"Microsoft.Windows.Explorer"},{"packagedAppId":"windows.immutablecontrolpanel"},{"packagedAppId":"Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"}]}""";

    /// <summary>OEM taskbar XML path (LayoutXMLPath). FirstLogon still writes per-user LayoutModification.xml after Cursor/Zen.</summary>
    public const string TaskbarLayoutOemGuestPath = @"C:\Windows\OEM\TaskbarLayoutModification.xml";

    /// <summary>Default-profile / OEM taskbar replace list (Explorer + Terminal).</summary>
    public const string TaskbarLayoutBaselineXml =
        """
        <?xml version="1.0" encoding="utf-8"?>
        <LayoutModificationTemplate
         xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
         xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
         xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
         xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
         Version="1">
          <CustomTaskbarLayoutCollection PinListPlacement="Replace">
            <defaultlayout:TaskbarLayout>
              <taskbar:TaskbarPinList>
                <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
                <taskbar:UWA AppUserModelID="Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" />
              </taskbar:TaskbarPinList>
            </defaultlayout:TaskbarLayout>
          </CustomTaskbarLayoutCollection>
        </LayoutModificationTemplate>
        """;
}
