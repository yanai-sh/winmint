namespace WinMint.Orchestrator;

/// <summary>Test vs Gate B work roots and lane-implied package strictness.</summary>
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

    public static bool ResolvePackageStrict(
        ImageQualityLane lane,
        PackageStrictOverride packageStrict) =>
        packageStrict switch
        {
            PackageStrictOverride.FromLane => lane == ImageQualityLane.Release,
            PackageStrictOverride.Force => true,
            PackageStrictOverride.Suppress => false,
            _ => throw new ArgumentOutOfRangeException(
                nameof(packageStrict),
                packageStrict,
                "Unsupported package-strict override."),
        };
}
