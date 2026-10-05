using System.Runtime.InteropServices;

namespace WinMint.Provisioning;

internal static class ShellDesktopPins
{
    private const string Arm64Url =
        "https://github.com/amnweb/thide/releases/download/v0.1.3/thide-0.1.3-arm64-portable.zip";

    private const string Arm64Sha =
        "85f1c2d91265654291c6cd448869ae53958455b551d98ac05d92711f3a4eea23";

    private const string X64Url =
        "https://github.com/amnweb/thide/releases/download/v0.1.3/thide-0.1.3-x64-portable.zip";

    private const string X64Sha =
        "d33bdc8b0468265924e7374286e578657a29c8c85edca4a9bddb197850afd97f";

    internal readonly record struct ThidePin(string Url, string Sha256Hex, string ZipFileName);

    internal static ThidePin ResolveThidePin(string? architectureOverride = null)
    {
        if (IsArm64(architectureOverride))
        {
            return new ThidePin(Arm64Url, Arm64Sha, "thide-0.1.3-arm64-portable.zip");
        }

        return new ThidePin(X64Url, X64Sha, "thide-0.1.3-x64-portable.zip");
    }

    private static bool IsArm64(string? architectureOverride)
    {
        if (!string.IsNullOrWhiteSpace(architectureOverride))
        {
            return architectureOverride.Equals("arm64", StringComparison.OrdinalIgnoreCase);
        }

        return RuntimeInformation.ProcessArchitecture is Architecture.Arm64;
    }
}
