namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon desktop-surface apply (ADR-015 window-management axis).
/// Taskbar chrome goes through <see cref="IGuestMachine.ApplyShellChrome"/> directly.
/// </summary>
public static class ShellSurfaces
{
    /// <summary>Apply YASB/tHide/Komorebi desktop assets (fail-open job).</summary>
    public static async Task ApplyDesktopAsync(
        IGuestMachine guest,
        IReadOnlyList<string> selectedWingetIds,
        CancellationToken ct = default)
    {
        ShellDesktopRequest request = new(
            selectedWingetIds,
            guest.Processes,
            guest.AssetDownload,
            ShellDesktopLayout.GuestDesktopRoot,
            ShellDesktopLayout.DefaultThideInstallDir,
            ShellDesktopLayout.DefaultYasbConfigDir,
            ShellDesktopLayout.DefaultKomorebiConfigDir,
            ShellDesktopLayout.DefaultWhkdrcPath);
        _ = await ShellDesktop.ApplyAsync(request, ct).ConfigureAwait(false);
    }
}
