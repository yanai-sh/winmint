namespace WinMint.Provisioning;

internal static class WindowsTerminalSettingsPath
{
    internal static string? Resolve()
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
