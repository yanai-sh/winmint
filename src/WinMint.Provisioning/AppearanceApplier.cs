using System.Runtime.Versioning;
using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>Hidden Win32 theme apply for <see cref="AppearanceOnce"/> (no hard-gate).</summary>
internal static class AppearanceApplier
{
    private const string PersonalizeSubKey =
        @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";

    [SupportedOSPlatform("windows")]
    public static void ApplyTheme(string theme)
    {
        int light = theme.Equals("Light", StringComparison.OrdinalIgnoreCase) ? 1
            : theme.Equals("Dark", StringComparison.OrdinalIgnoreCase) ? 0
            : -1;
        if (light < 0)
        {
            return;
        }

        using RegistryKey key = Registry.CurrentUser.CreateSubKey(PersonalizeSubKey)
            ?? throw new InvalidOperationException($"Cannot open HKCU\\{PersonalizeSubKey}.");
        key.SetValue("AppsUseLightTheme", light, RegistryValueKind.DWord);
        key.SetValue("SystemUsesLightTheme", light, RegistryValueKind.DWord);
    }
}
