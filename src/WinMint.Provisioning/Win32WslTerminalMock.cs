namespace WinMint.Provisioning;

/// <summary>Best-effort Windows Terminal profiles so a mocked WSL job still paints a distro tab.</summary>
public static class Win32WslTerminalMock
{
    public static void TryStage(IEnumerable<string> distroNames)
    {
        try
        {
            Stage(distroNames);
        }
        catch
        {
            // Best-effort — hypervisor mock must not fail-close on Terminal JSON.
        }
    }

    private static void Stage(IEnumerable<string> distroNames)
    {
        string? path = ResolveSettingsPath();
        if (path is null || !File.Exists(path))
        {
            return;
        }

        string json = File.ReadAllText(path);
        foreach (string distro in distroNames)
        {
            if (string.IsNullOrWhiteSpace(distro))
            {
                continue;
            }

            string name = distro.Equals("FedoraLinux", StringComparison.OrdinalIgnoreCase)
                ? "Fedora"
                : distro;
            if (json.Contains($"\"name\": \"{name}\"", StringComparison.OrdinalIgnoreCase)
                || json.Contains($"\"name\":\"{name}\"", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            // ponytail: first "list" insert; source-gen STJ if settings use comments/fragments.
            int list = json.IndexOf("\"list\"", StringComparison.OrdinalIgnoreCase);
            int bracket = list < 0 ? -1 : json.IndexOf('[', list);
            if (bracket < 0)
            {
                continue;
            }

            string escaped = name.Replace("\\", "\\\\", StringComparison.Ordinal)
                .Replace("\"", "\\\"", StringComparison.Ordinal);
            string profile =
                $"{{\"name\":\"{escaped}\",\"commandline\":\"cmd.exe /c echo WSL mocked\"}}";
            json = json.Insert(bracket + 1, profile + ",");
        }

        File.WriteAllText(path, json);
    }

    private static string? ResolveSettingsPath()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string unpackaged = Path.Combine(local, "Microsoft", "Windows Terminal", "settings.json");
        string packages = Path.Combine(local, "Packages");
        if (Directory.Exists(packages))
        {
            foreach (string dir in Directory.EnumerateDirectories(packages, "Microsoft.WindowsTerminal*"))
            {
                return Path.Combine(dir, "LocalState", "settings.json");
            }
        }

        return unpackaged;
    }
}
