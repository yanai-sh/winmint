using System.Text.Json;

namespace WinMint.Provisioning;

/// <summary>
/// Redacts staged secrets after Winlogon stamp (not HKLM DefaultPassword).
/// Guarantee: disk redact + no further use of the stamp password in MachineSetup.
/// Not a cryptographic in-process memory scrub (immutable strings live until GC).
/// </summary>
public sealed class FileSecretScrubber
{
    private readonly string _bundlePath;
    private readonly Action<string>? _log;

    public FileSecretScrubber(string bundlePath, Action<string>? log = null)
    {
        _bundlePath = bundlePath;
        _log = log;
    }

    public void Wipe(ProvisioningBundle bundle)
    {
        _ = bundle;
        if (!File.Exists(_bundlePath))
        {
            return;
        }

        byte[] bytes = File.ReadAllBytes(_bundlePath);
        BundleDto? dto = JsonSerializer.Deserialize(bytes, ProvisioningJsonContext.Default.BundleDto);
        if (dto is null)
        {
            throw new InvalidOperationException($"Secret wipe: failed to parse bundle {_bundlePath}");
        }

        BundleDto redacted = dto with { Password = "" };
        byte[] outBytes = JsonSerializer.SerializeToUtf8Bytes(redacted, ProvisioningJsonContext.Default.BundleDto);
        // ponytail: full DPAPI host→guest staging channel stays future if Smoke plaintext+wipe remains lab-ok
        File.WriteAllBytes(_bundlePath, outBytes);
        _log?.Invoke($"Secret wipe: redacted password in {_bundlePath}");
    }
}
