namespace WinMint.Orchestrator;

/// <summary>
/// Ported v1 Surface driver catalog (issue 63). Full device list for validation;
/// <see cref="WiredDeviceIds"/> gates end-to-end Plan wiring (SL7-only this ticket).
/// </summary>
public static class SurfaceDriverCatalog
{
    public const string SourceSurfaceCatalog = "surfaceCatalog";

    /// <summary>Device ids that emit <see cref="ServicingOpcode.InjectDrivers"/> at Plan.</summary>
    public static IReadOnlySet<string> WiredDeviceIds { get; } = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "surface-laptop-7",
    };

    public static IReadOnlyDictionary<string, SurfaceDriverDevice> Devices { get; } =
        BuildDevices().ToDictionary(d => d.Id, StringComparer.OrdinalIgnoreCase);

    public static bool TryGet(string deviceId, out SurfaceDriverDevice? device) =>
        Devices.TryGetValue(deviceId, out device);

    /// <summary>Normalize WIM/DISM arch (x64) to catalog form (amd64).</summary>
    public static string NormalizeArchitecture(string? arch)
    {
        if (string.IsNullOrWhiteSpace(arch))
        {
            return "";
        }

        string t = arch.Trim();
        return t.Equals("x64", StringComparison.OrdinalIgnoreCase) ? "amd64" : t.ToLowerInvariant();
    }

    private static IEnumerable<SurfaceDriverDevice> BuildDevices()
    {
        yield return new SurfaceDriverDevice(
            "surface-laptop-8-snapdragon",
            "arm64",
            "108705",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108705",
            @"^SurfaceLaptop8withSnapdragon_Win11_28000_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            28000);
        yield return new SurfaceDriverDevice(
            "surface-laptop-business-8-intel",
            "amd64",
            "108669",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108669",
            @"^SurfaceLaptop8withIntel_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            26100);
        yield return new SurfaceDriverDevice(
            "surface-laptop-13-inch-1-snapdragon",
            "arm64",
            "108198",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108198",
            @"^SurfaceLaptop_13in_1st_Edition_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            26100);
        yield return new SurfaceDriverDevice(
            "surface-laptop-business-13-inch-1-intel",
            "amd64",
            "108670",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108670",
            @"^SurfaceLaptopforBusiness13in1stEdIntel_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            26100);
        yield return new SurfaceDriverDevice(
            "surface-laptop-5g-business-7-intel",
            "amd64",
            "108347",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108347",
            @"^SurfaceLaptop7-5GforBusinesswithIntel_Win11_22631_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            22631);
        yield return new SurfaceDriverDevice(
            "surface-laptop-7",
            "arm64",
            "106120",
            "https://www.microsoft.com/en-us/download/details.aspx?id=106120",
            @"^SurfaceLaptop7_ARM_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            26100);
        yield return new SurfaceDriverDevice(
            "surface-laptop-business-7",
            "amd64",
            "108014",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108014",
            @"^SurfaceLaptop7withIntel_Win11_22631_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            22631);
        yield return new SurfaceDriverDevice(
            "surface-pro-11-snapdragon",
            "arm64",
            "106119",
            "https://www.microsoft.com/en-us/download/details.aspx?id=106119",
            @"^SurfacePro11_ARM_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            26100);
        yield return new SurfaceDriverDevice(
            "surface-pro-11-intel",
            "amd64",
            "108013",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108013",
            @"^SurfacePro11withIntel_Win11_22631_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            22631);
        yield return new SurfaceDriverDevice(
            "surface-pro-12-business-intel",
            "amd64",
            "108671",
            "https://www.microsoft.com/en-us/download/details.aspx?id=108671",
            @"^SurfacePro12withIntel_Win11_\d+_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
            26100);
    }
}

public sealed record SurfaceDriverDevice(
    string Id,
    string Architecture,
    string DownloadCenterId,
    string DetailsUrl,
    string ExpectedFileNameRegex,
    int MinimumWindowsBuild);
