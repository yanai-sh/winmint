namespace WinMint.Provisioning;

/// <summary>
/// FirstLogon shell surfaces (ADR-015): taskbar chrome and window-management desktop axes.
/// JobRunner calls this seam; layout/pin/Win32 details stay implementation-local.
/// </summary>
public static class ShellSurfaces
{
    /// <summary>Apply Start/taskbar/bloom chrome via the guest adapter.</summary>
    public static bool TryApplyChrome(
        IGuestMachine guest,
        IReadOnlyList<string> selectedWingetIds,
        bool packageStrict,
        bool failOpen = false) =>
        guest.ApplyShellChrome(
            new ShellChromeRequest(
                FailOpen: failOpen,
                SelectedWingetIds: selectedWingetIds,
                RequireSelectedPins: packageStrict));

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
