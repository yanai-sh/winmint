using System.Text.Json;
using System.Text.Json.Nodes;

namespace WinMint.Provisioning;

/// <summary>Wipes staged secrets after Winlogon stamp (not the live DefaultPassword value).</summary>
public sealed class FileSecretScrubber : ISecretScrubber
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
        if (!File.Exists(_bundlePath))
        {
            return;
        }

        string text = File.ReadAllText(_bundlePath);
        JsonNode? root = JsonNode.Parse(text);
        if (root is JsonObject obj && obj.ContainsKey("password"))
        {
            obj["password"] = "";
            File.WriteAllText(_bundlePath, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            _log?.Invoke($"Secret wipe: redacted password in {_bundlePath}");
        }
    }
}
