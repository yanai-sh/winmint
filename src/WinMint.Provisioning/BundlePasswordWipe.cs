using Microsoft.Extensions.Logging;

using WinMint.Contracts;

namespace WinMint.Provisioning;

/// <summary>
/// Redacts staged secrets after Winlogon stamp (not HKLM DefaultPassword).
/// Guarantee: disk redact + no further use of the stamp password in MachineSetup.
/// Not a cryptographic in-process memory scrub (immutable strings live until GC).
/// </summary>
internal static class BundlePasswordWipe
{
    internal static void WipeBundlePassword(string bundlePath, ILogger? logger = null)
    {
        if (!File.Exists(bundlePath))
        {
            return;
        }

        byte[] bytes = File.ReadAllBytes(bundlePath);
        if (!GuestBundleWire.TryParse(bytes, out BundleFile? file, out GuestBundleWireError error))
        {
            throw new InvalidOperationException($"Secret wipe: {error.Message} ({bundlePath})");
        }

        File.WriteAllText(bundlePath, GuestBundleWire.Write(file with { Password = "" }));
        if (logger is not null)
        {
            GuestLog.SecretWiped(logger, bundlePath);
        }
    }
}
