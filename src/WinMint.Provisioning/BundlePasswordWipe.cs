using System.Text.Json;

namespace WinMint.Provisioning;

/// <summary>
/// Redacts staged secrets after Winlogon stamp (not HKLM DefaultPassword).
/// Guarantee: disk redact + no further use of the stamp password in MachineSetup.
/// Not a cryptographic in-process memory scrub (immutable strings live until GC).
/// </summary>
internal static class BundlePasswordWipe
{
    internal static void WipeBundlePassword(string bundlePath, Action<string>? log)
    {
        if (!File.Exists(bundlePath))
        {
            return;
        }

        byte[] bytes = File.ReadAllBytes(bundlePath);
        BundleFile? dto = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.BundleFile);
        if (dto is null)
        {
            throw new InvalidOperationException($"Secret wipe: failed to parse bundle {bundlePath}");
        }

        BundleFile redacted = dto with { Password = "" };
        byte[] outBytes = JsonSerializer.SerializeToUtf8Bytes(redacted, ProvisioningJsonContext.Default.BundleFile);
        // ponytail: full DPAPI host→guest staging channel stays future if Smoke plaintext+wipe remains lab-ok
        File.WriteAllBytes(bundlePath, outBytes);
        log?.Invoke($"Secret wipe: redacted password in {bundlePath}");
    }
}
