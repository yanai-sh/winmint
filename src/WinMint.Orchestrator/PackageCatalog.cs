using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>Shipped package manifest (<c>config/packages.json</c>). Debloat uses <see cref="CapabilityCatalog"/>; this catalog covers metal installs only.</summary>
public sealed class PackageCatalog
{
    private static readonly Lazy<PackageCatalog> Embedded = new(LoadEmbedded);

    private readonly Dictionary<string, PackageToolEntry> _toolsByKey;
    private readonly Dictionary<string, PackageToolEntry> _toolsByInstallId;
    private readonly Dictionary<string, WslDistroEntry> _wslByKey;
    private readonly Dictionary<string, WslDistroEntry> _wslByInstallId;

    private PackageCatalog(
        Dictionary<string, PackageToolEntry> toolsByKey,
        Dictionary<string, PackageToolEntry> toolsByInstallId,
        Dictionary<string, WslDistroEntry> wslByKey,
        Dictionary<string, WslDistroEntry> wslByInstallId)
    {
        _toolsByKey = toolsByKey;
        _toolsByInstallId = toolsByInstallId;
        _wslByKey = wslByKey;
        _wslByInstallId = wslByInstallId;
    }

    public static PackageCatalog Default => Embedded.Value;

    public static PackageCatalog LoadFromJson(ReadOnlySpan<byte> utf8)
    {
        PackageCatalogFile? file = JsonSerializer.Deserialize(utf8, PackageCatalogJsonContext.Default.PackageCatalogFile);
        if (file is null)
        {
            throw new InvalidOperationException("Package catalog JSON did not deserialize.");
        }

        return Build(file);
    }

    public static PackageCatalog LoadFromFile(string path) =>
        LoadFromJson(File.ReadAllBytes(path));

    public bool TryGetToolByKey(string key, out PackageToolEntry entry) =>
        _toolsByKey.TryGetValue(key, out entry!);

    public bool TryGetToolByInstallId(string installId, out PackageToolEntry entry) =>
        _toolsByInstallId.TryGetValue(installId, out entry!);

    public bool TryGetWslByProfileToken(string token, out WslDistroEntry entry)
    {
        if (_wslByKey.TryGetValue(token, out entry!))
        {
            return true;
        }

        return _wslByInstallId.TryGetValue(token, out entry!);
    }

    /// <summary>Resolve curated chip keys to Profile install ids grouped by package manager source.</summary>
    public PackageSelection ResolveToolKeys(IEnumerable<string> keys)
    {
        List<string> winget = [];
        List<string> scoop = [];
        HashSet<string> seenWinget = new(StringComparer.OrdinalIgnoreCase);
        HashSet<string> seenScoop = new(StringComparer.OrdinalIgnoreCase);

        foreach (string raw in keys)
        {
            string key = raw.Trim();
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            if (!_toolsByKey.TryGetValue(key, out PackageToolEntry? tool))
            {
                throw new InvalidOperationException($"Unknown package catalog tool key '{key}'.");
            }

            if (string.Equals(tool.Source, "winget", StringComparison.OrdinalIgnoreCase)
                || string.Equals(tool.Source, "store", StringComparison.OrdinalIgnoreCase))
            {
                if (seenWinget.Add(tool.InstallId))
                {
                    winget.Add(tool.InstallId);
                }
            }
            else if (string.Equals(tool.Source, "scoop", StringComparison.OrdinalIgnoreCase))
            {
                if (seenScoop.Add(tool.InstallId))
                {
                    scoop.Add(tool.InstallId);
                }
            }
            else
            {
                throw new InvalidOperationException(
                    $"Tool '{key}' uses unsupported source '{tool.Source}'.");
            }
        }

        return new PackageSelection(winget, scoop, []);
    }

    /// <summary>Resolve WSL chip keys / profile tokens to catalog profile tokens for <c>packages.wsl</c>.</summary>
    public IReadOnlyList<string> ResolveWslTokens(IEnumerable<string> tokens)
    {
        List<string> distros = [];
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        foreach (string raw in tokens)
        {
            string token = raw.Trim();
            if (string.IsNullOrWhiteSpace(token))
            {
                continue;
            }

            if (!TryGetWslByProfileToken(token, out WslDistroEntry? entry))
            {
                throw new InvalidOperationException($"Unknown WSL catalog token '{token}'.");
            }

            if (seen.Add(entry.ProfileToken))
            {
                distros.Add(entry.ProfileToken);
            }
        }

        return distros;
    }

    public static string? ResolveWingetArchitectureFlag(PackageToolEntry tool, string imageArchitecture)
    {
        if (!string.Equals(NormalizeArch(imageArchitecture), "arm64", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (!tool.Architectures.Any(a => string.Equals(a, "arm64", StringComparison.OrdinalIgnoreCase)))
        {
            return null;
        }

        return "arm64";
    }

    public static string NormalizeArch(string architecture)
    {
        string arch = architecture.Trim();
        if (arch.Equals("x64", StringComparison.OrdinalIgnoreCase)
            || arch.Equals("amd64", StringComparison.OrdinalIgnoreCase))
        {
            return "amd64";
        }

        if (arch.Equals("aarch64", StringComparison.OrdinalIgnoreCase))
        {
            return "arm64";
        }

        return arch.ToLowerInvariant();
    }

    public static string DefaultImageArchitecture => "arm64";

    public static string EffectiveImageArchitecture(RunOptions? run) =>
        string.IsNullOrWhiteSpace(run?.ImageArchitecture)
            ? DefaultImageArchitecture
            : NormalizeArch(run.ImageArchitecture);

    // ponytail: product-constant winget always non-empty (ADR-009); phase is arch-only until constants become optional.
    public static PackagePhase EffectivePackagePhase(string imageArchitecture) =>
        string.Equals(NormalizeArch(imageArchitecture), "arm64", StringComparison.OrdinalIgnoreCase)
            ? PackagePhase.WingetImport
            : PackagePhase.PerJob;

    public IReadOnlyList<string> ToolCatalogKeys => _toolsByKey.Keys.ToList();

    public IReadOnlySet<string> ScoopBucketsForInstallIds(IEnumerable<string> installIds)
    {
        HashSet<string> buckets = new(StringComparer.OrdinalIgnoreCase);
        foreach (string installId in installIds)
        {
            if (_toolsByInstallId.TryGetValue(installId, out PackageToolEntry? tool)
                && string.Equals(tool.Source, "scoop", StringComparison.OrdinalIgnoreCase))
            {
                buckets.Add(tool.ScoopBucket ?? "main");
            }
        }

        return buckets;
    }

    public IReadOnlyList<string> ValidateProfilePackages(
        Profile profile,
        string imageArchitecture,
        out Failure? failure)
    {
        failure = null;
        string imageArch = NormalizeArch(imageArchitecture);
        List<string> wingetAuditTargets = [];
        IReadOnlyList<string> wingetIds = ProductPosture.MergeWinget(profile.WingetPackages);

        foreach (string installId in wingetIds)
        {
            if (!_toolsByInstallId.TryGetValue(installId, out PackageToolEntry? tool)
                || !string.Equals(tool.Source, "winget", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(tool.Source, "store", StringComparison.OrdinalIgnoreCase))
            {
                failure = new Failure(
                    "packages.catalog.unknown",
                    $"packages.winget id '{installId}' is not in the shipped package catalog.");
                return [];
            }

            if (imageArch == "arm64"
                && !tool.Architectures.Any(a => string.Equals(a, "arm64", StringComparison.OrdinalIgnoreCase)))
            {
                failure = new Failure(
                    "packages.catalog.unsupportedArch",
                    $"{tool.DisplayName} ({installId}) does not support arm64 in the package catalog.");
                return [];
            }

            wingetAuditTargets.Add(installId);
        }

        foreach (string installId in profile.ScoopPackages)
        {
            if (!_toolsByInstallId.TryGetValue(installId, out PackageToolEntry? tool)
                || !string.Equals(tool.Source, "scoop", StringComparison.OrdinalIgnoreCase))
            {
                failure = new Failure(
                    "packages.catalog.unknown",
                    $"packages.scoop id '{installId}' is not in the shipped package catalog.");
                return [];
            }

            if (imageArch == "arm64"
                && !tool.Architectures.Any(a => string.Equals(a, "arm64", StringComparison.OrdinalIgnoreCase)))
            {
                failure = new Failure(
                    "packages.catalog.unsupportedArch",
                    $"{tool.DisplayName} ({installId}) does not support arm64 in the package catalog.");
                return [];
            }
        }

        foreach (string token in profile.WslDistros)
        {
            if (!TryGetWslByProfileToken(token, out WslDistroEntry? entry))
            {
                failure = new Failure(
                    "packages.catalog.unknown",
                    $"packages.wsl token '{token}' is not in the shipped WSL catalog.");
                return [];
            }

            if (imageArch == "arm64"
                && !entry.Architectures.Any(a => string.Equals(a, "arm64", StringComparison.OrdinalIgnoreCase)))
            {
                failure = new Failure(
                    "packages.catalog.unsupportedArch",
                    $"{entry.DisplayName} ({token}) does not support arm64 in the WSL catalog.");
                return [];
            }
        }

        return wingetAuditTargets;
    }

    private static PackageCatalog LoadEmbedded()
    {
        Assembly assembly = typeof(PackageCatalog).Assembly;
        string resourceName = assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("packages.json", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("Embedded package catalog resource not found.");
        using Stream stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Failed to open embedded catalog: {resourceName}");
        using MemoryStream buffer = new();
        stream.CopyTo(buffer);
        return LoadFromJson(buffer.ToArray());
    }

    private static PackageCatalog Build(PackageCatalogFile file)
    {
        Dictionary<string, PackageToolEntry> toolsByKey = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, PackageToolEntry> toolsByInstallId = new(StringComparer.OrdinalIgnoreCase);
        if (file.Tools is not null)
        {
            foreach ((string key, PackageToolDto dto) in file.Tools)
            {
                if (string.IsNullOrWhiteSpace(dto.Id))
                {
                    throw new InvalidOperationException($"Tool '{key}' is missing id.");
                }

                if (dto.Source is not ("winget" or "store" or "scoop"))
                {
                    throw new InvalidOperationException(
                        $"Tool '{key}' must use winget, store, or scoop (got '{dto.Source}').");
                }

                string[] arch = dto.Architectures ?? [];
                PackageToolEntry entry = new(
                    key,
                    dto.DisplayName ?? key,
                    dto.Source,
                    dto.Id,
                    arch,
                    dto.ScoopBucket);
                toolsByKey[key] = entry;
                toolsByInstallId[dto.Id] = entry;
            }
        }

        Dictionary<string, WslDistroEntry> wslByKey = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, WslDistroEntry> wslByInstallId = new(StringComparer.OrdinalIgnoreCase);
        if (file.WslDistros is not null)
        {
            foreach ((string key, WslDistroDto dto) in file.WslDistros)
            {
                string installId = dto.InstallId ?? key;
                string installKind = dto.InstallKind ?? "store";
                WslDistroEntry entry = new(
                    key,
                    dto.DisplayName ?? key,
                    installKind,
                    installId,
                    dto.Repo,
                    dto.Assets?.Arm64,
                    dto.Assets?.Amd64,
                    dto.Architectures ?? ["arm64", "amd64"]);
                wslByKey[key] = entry;
                wslByInstallId[installId] = entry;
            }
        }

        return new PackageCatalog(toolsByKey, toolsByInstallId, wslByKey, wslByInstallId);
    }
}

public sealed record PackageToolEntry(
    string CatalogKey,
    string DisplayName,
    string Source,
    string InstallId,
    IReadOnlyList<string> Architectures,
    string? ScoopBucket = null);

public sealed record WslDistroEntry(
    string ProfileToken,
    string DisplayName,
    string InstallKind,
    string InstallId,
    string? FromFileRepo,
    IReadOnlyList<string>? FromFileAssetNamesArm64,
    IReadOnlyList<string>? FromFileAssetNamesAmd64,
    IReadOnlyList<string> Architectures)
{
    public IReadOnlyList<string> FromFileAssetNamesFor(string imageArchitecture)
    {
        string arch = PackageCatalog.NormalizeArch(imageArchitecture);
        if (arch == "arm64")
        {
            return FromFileAssetNamesArm64 ?? [];
        }

        return FromFileAssetNamesAmd64 ?? [];
    }
}

public sealed record PackageSelection(
    IReadOnlyList<string> WingetInstallIds,
    IReadOnlyList<string> ScoopInstallIds,
    IReadOnlyList<string> WslProfileTokens);

internal sealed class PackageCatalogFile
{
    [JsonPropertyName("tools")]
    public Dictionary<string, PackageToolDto>? Tools { get; set; }

    [JsonPropertyName("wslDistros")]
    public Dictionary<string, WslDistroDto>? WslDistros { get; set; }
}

internal sealed class PackageToolDto
{
    [JsonPropertyName("displayName")]
    public string? DisplayName { get; set; }

    [JsonPropertyName("source")]
    public string Source { get; set; } = "";

    [JsonPropertyName("id")]
    public string? Id { get; set; }

    [JsonPropertyName("architectures")]
    public string[]? Architectures { get; set; }

    [JsonPropertyName("scoopBucket")]
    public string? ScoopBucket { get; set; }
}

internal sealed class WslDistroDto
{
    [JsonPropertyName("displayName")]
    public string? DisplayName { get; set; }

    [JsonPropertyName("installKind")]
    public string? InstallKind { get; set; }

    [JsonPropertyName("installId")]
    public string? InstallId { get; set; }

    [JsonPropertyName("repo")]
    public string? Repo { get; set; }

    [JsonPropertyName("assets")]
    public WslAssetsDto? Assets { get; set; }

    [JsonPropertyName("architectures")]
    public string[]? Architectures { get; set; }
}

internal sealed class WslAssetsDto
{
    [JsonPropertyName("arm64")]
    public string[]? Arm64 { get; set; }

    [JsonPropertyName("amd64")]
    public string[]? Amd64 { get; set; }
}

[JsonSerializable(typeof(PackageCatalogFile))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PackageCatalogJsonContext : JsonSerializerContext;
