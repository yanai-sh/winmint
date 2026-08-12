namespace WinMint.Orchestrator;

/// <summary>Test vs Gate B work roots. Package strictness is caller-owned (Cli/Wizard).</summary>
public static class HostDefaults
{
    public static string DefaultWorkDirectory { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "work");

    /// <summary>Gate B wipe ISO workdir — same as just primary-gate / -PrimaryGate.</summary>
    public static string GateBWorkDirectory { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WinMint",
            "work",
            "gate-b");

    public static string ResolveWorkDirectory(ImageQualityLane lane, string? workDirectory = null) =>
        string.IsNullOrWhiteSpace(workDirectory)
            ? lane == ImageQualityLane.Release ? GateBWorkDirectory : DefaultWorkDirectory
            : workDirectory.Trim();
}
