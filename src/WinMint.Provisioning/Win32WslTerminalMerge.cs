using System.Text.Json;
using System.Text.Json.Nodes;

namespace WinMint.Provisioning;

/// <summary>Fail-open merge of preferred WSL profile into existing Windows Terminal settings.</summary>
public static class Win32WslTerminalMerge
{
    public sealed record MergeOutcome(bool Applied, string Note);

    public static MergeOutcome TryMerge(string distroInstallId, string? linuxUsername, string settingsPath)
    {
        try
        {
            return Merge(distroInstallId, linuxUsername, settingsPath);
        }
        catch (Exception ex)
        {
            return new MergeOutcome(false, $"merge failed: {ex.Message}");
        }
    }

    internal static MergeOutcome Merge(string distroInstallId, string? linuxUsername, string settingsPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(distroInstallId);
        ArgumentException.ThrowIfNullOrWhiteSpace(settingsPath);

        if (!File.Exists(settingsPath))
        {
            return new MergeOutcome(false, "settings.json missing");
        }

        string json = File.ReadAllText(settingsPath);
        JsonNode? root = JsonNode.Parse(json);
        if (root is not JsonObject rootObj)
        {
            return new MergeOutcome(false, "settings.json not an object");
        }

        JsonArray? list = rootObj["profiles"]?["list"]?.AsArray();
        if (list is null)
        {
            return new MergeOutcome(false, "profiles.list missing");
        }

        JsonObject? profile = FindWslProfile(list, distroInstallId);
        if (profile is null)
        {
            return new MergeOutcome(false, $"no WSL profile for {distroInstallId}");
        }

        string? guid = profile["guid"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(guid))
        {
            return new MergeOutcome(false, "WSL profile has no guid");
        }

        rootObj["defaultProfile"] = guid;

        if (!string.IsNullOrWhiteSpace(linuxUsername))
        {
            string home = $"//wsl.localhost/{distroInstallId}/home/{linuxUsername.Trim()}";
            profile["startingDirectory"] = home;
        }

        string merged = rootObj.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(settingsPath, merged);

        string note = string.IsNullOrWhiteSpace(linuxUsername)
            ? $"defaultProfile={guid}"
            : $"defaultProfile={guid}; startingDirectory set";
        return new MergeOutcome(true, note);
    }

    private static JsonObject? FindWslProfile(JsonArray list, string distroInstallId)
    {
        string preferredName = TerminalProfileNameForInstallId(distroInstallId);
        foreach (JsonNode? node in list)
        {
            if (node is not JsonObject obj)
            {
                continue;
            }

            if (!IsWslProfile(obj))
            {
                continue;
            }

            if (ProfileMatchesDistro(obj, distroInstallId, preferredName))
            {
                return obj;
            }
        }

        return null;
    }

    private static bool IsWslProfile(JsonObject profile)
    {
        string? source = profile["source"]?.GetValue<string>();
        if (string.Equals(source, "Windows.Terminal.Wsl", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        string? commandline = profile["commandline"]?.GetValue<string>();
        return commandline is not null
            && commandline.Contains("wsl.exe", StringComparison.OrdinalIgnoreCase);
    }

    private static bool ProfileMatchesDistro(JsonObject profile, string installId, string preferredName)
    {
        string? name = profile["name"]?.GetValue<string>();
        if (!string.IsNullOrWhiteSpace(name)
            && (name.Equals(preferredName, StringComparison.OrdinalIgnoreCase)
                || name.Equals(installId, StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        string? wslDistro = profile["wslDistro"]?.GetValue<string>();
        if (!string.IsNullOrWhiteSpace(wslDistro)
            && wslDistro.Equals(installId, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        string? commandline = profile["commandline"]?.GetValue<string>();
        if (!string.IsNullOrWhiteSpace(commandline)
            && commandline.Contains($"-d {installId}", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return false;
    }

    internal static string TerminalProfileNameForInstallId(string installId) =>
        installId.Equals("FedoraLinux", StringComparison.OrdinalIgnoreCase) ? "Fedora" : installId;
}
