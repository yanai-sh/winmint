namespace WinMint.Orchestrator;

/// <summary>Test vs Gate B work roots and lane-implied package-strict. Cited by HostCompile / Wizard recipe.</summary>
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
            "sl7-primary");

    public static string ResolveWorkDirectory(ImageQualityLane lane, string? workDirectory = null) =>
        string.IsNullOrWhiteSpace(workDirectory)
            ? lane == ImageQualityLane.Release ? GateBWorkDirectory : DefaultWorkDirectory
            : workDirectory.Trim();

    public static bool PackageStrictFor(ImageQualityLane lane) => lane == ImageQualityLane.Release;
}
