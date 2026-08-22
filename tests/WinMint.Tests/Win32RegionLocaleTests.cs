using System.Runtime.Versioning;

using WinMint.Provisioning;

namespace WinMint.Tests;

/// <summary>
/// GetUserDefaultLocaleName is a real kernel32 export (NativeMethods.txt).
/// Do not Set-Culture from just check — user locale is process/host global.
/// </summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public class Win32RegionLocaleTests
{
    [Fact]
    public void Read_locale_comes_from_GetUserDefaultLocaleName()
    {
        RegionState state = new Win32RegionSnapshot().Read();
        Assert.False(string.IsNullOrWhiteSpace(state.Locale));
        Assert.True(state.Locale.Length >= 2, $"locale '{state.Locale}'");
    }
}
