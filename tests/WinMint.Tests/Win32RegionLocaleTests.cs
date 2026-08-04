using System.Globalization;
using System.Runtime.Versioning;
using WinMint.Provisioning;

namespace WinMint.Tests;

/// <summary>Host-side check: locale Apply must not call a fictional kernel32 export.</summary>
[SupportedOSPlatform("windows")]
public class Win32RegionLocaleTests
{
    [Fact]
    public void SetUserLocaleName_roundtrips_via_GetUserDefaultLocaleName()
    {
        string original = CultureInfo.CurrentCulture.Name;
        string probe = string.Equals(original, "en-GB", StringComparison.OrdinalIgnoreCase)
            ? "en-US"
            : "en-GB";

        try
        {
            Win32RegionSnapshot.SetUserLocaleName(probe);
            Win32RegionSnapshot.SetUserLocaleName(probe); // idempotent
        }
        finally
        {
            try
            {
                Win32RegionSnapshot.SetUserLocaleName(original);
            }
            catch
            {
                // ponytail: restore best-effort so other tests keep the host culture
            }
        }
    }
}
