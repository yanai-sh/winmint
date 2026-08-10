namespace WinMint.Orchestrator;

/// <summary>
/// Surface driver catalog (issue 63 / #90). Alpha ships SL7 only — catalog rows are the wired set.
/// </summary>
public static class SurfaceDriverCatalog
{
    public const string SourceSurfaceCatalog = "surfaceCatalog";

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
            "surface-laptop-7",
            "arm64",
            "106120",
            "https://www.microsoft.com/en-us/download/details.aspx?id=106120",
            @"^SurfaceLaptop7_ARM_Win11_26100_\d{2}\.\d{3}\.\d+\.\d+\.msi$",
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
