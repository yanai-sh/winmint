using System.Reflection;
using System.Collections.Frozen;
using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

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

    public static Result<PackageCatalog, Failure> TryLoadFromJson(ReadOnlySpan<byte> utf8)
    {
        PackageCatalogFile? file;
        try
        {
            file = JsonSerializer.Deserialize(utf8, PackageCatalogJsonContext.Default.PackageCatalogFile);
        }
        catch (JsonException ex)
        {
            return Result.Fail<PackageCatalog, Failure>(
                new Failure("packages.catalog.invalidJson", ex.Message));
        }

        if (file is null)
        {
            return Result.Fail<PackageCatalog, Failure>(
                new Failure("packages.catalog.invalidJson", "Package catalog JSON did not deserialize."));
        }

        try
        {
            return Result.Ok<PackageCatalog, Failure>(Build(file));
        }
        catch (InvalidOperationException ex)
        {
            return Result.Fail<PackageCatalog, Failure>(
                new Failure("packages.catalog.invalid", ex.Message));
        }
    }

    public static Result<PackageCatalog, Failure> TryLoadFromFile(string path)
    {
        byte[] bytes;
        try
        {
            bytes = File.ReadAllBytes(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return Result.Fail<PackageCatalog, Failure>(
                new Failure("packages.catalog.readFailed", ex.Message));
        }

        return TryLoadFromJson(bytes);
    }

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
    public Result<PackageSelection, Failure> ResolveToolKeys(IEnumerable<string> keys)
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
                return Result.Fail<PackageSelection, Failure>(
                    new Failure(
                        "packages.catalog.unknown",
                        $"Unknown package catalog tool key '{key}'."));
            }

            if (tool.Source is PackageToolSource.Winget or PackageToolSource.Store)
            {
                if (seenWinget.Add(tool.InstallId))
                {
                    winget.Add(tool.InstallId);
                }
            }
            else if (tool.Source is PackageToolSource.Scoop)
            {
                if (seenScoop.Add(tool.InstallId))
                {
                    scoop.Add(tool.InstallId);
                }
            }
            else
            {
                return Result.Fail<PackageSelection, Failure>(
                    new Failure(
                        "packages.catalog.unsupportedSource",
                        $"Tool '{key}' uses unsupported source '{tool.Source.ToWire()}'."));
            }
        }

        return Result.Ok<PackageSelection, Failure>(
            new PackageSelection(winget.ToArray(), scoop.ToArray(), []));
    }

    /// <summary>Resolve WSL chip keys / profile tokens to catalog profile tokens for <c>packages.wsl</c>.</summary>
    public Result<IReadOnlyList<string>, Failure> ResolveWslTokens(IEnumerable<string> tokens)
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
                return Result.Fail<IReadOnlyList<string>, Failure>(
                    new Failure(
                        "packages.catalog.unknown",
                        $"Unknown WSL catalog token '{token}'."));
            }

            if (seen.Add(entry.ProfileToken))
            {
                distros.Add(entry.ProfileToken);
            }
        }

        return Result.Ok<IReadOnlyList<string>, Failure>(distros.ToArray());
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

    public IReadOnlyList<string> ToolCatalogKeys => _toolsByKey.Keys.ToArray();

    /// <summary>Validate maintainer invariants for the shipped package catalog.</summary>
    public IReadOnlyList<string> Validate()
    {
        List<string> errors = [];
        foreach (string key in ToolCatalogKeys)
        {
            if (!TryGetToolByKey(key, out PackageToolEntry? tool))
            {
                continue;
            }

            if (tool.Architectures.Count == 0
                || !tool.Architectures.Any(a => string.Equals(a, "arm64", StringComparison.OrdinalIgnoreCase)))
            {
                errors.Add($"Tool '{key}' ({tool.InstallId}) missing arm64 in catalog architectures.");
            }

            if (tool.Source is PackageToolSource.Scoop)
            {
                string bucket = tool.ScoopBucket ?? "main";
                if (bucket is not ("main" or "extras"))
                {
                    errors.Add($"Tool '{key}' has unsupported scoopBucket '{bucket}'.");
                }

                if ((tool.InstallId is "komorebi" or "whkd") && bucket != "extras")
                {
                    errors.Add($"Tool '{key}' must declare scoopBucket extras.");
                }
            }
        }

        return errors.ToArray();
    }

    public IReadOnlySet<string> ScoopBucketsForInstallIds(IEnumerable<string> installIds)
    {
        HashSet<string> buckets = new(StringComparer.OrdinalIgnoreCase);
        foreach (string installId in installIds)
        {
            if (_toolsByInstallId.TryGetValue(installId, out PackageToolEntry? tool)
                && tool.Source is PackageToolSource.Scoop)
            {
                buckets.Add(tool.ScoopBucket ?? "main");
            }
        }

        return buckets.ToFrozenSet(StringComparer.OrdinalIgnoreCase);
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
                || tool.Source is not (PackageToolSource.Winget or PackageToolSource.Store))
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
                || tool.Source is not PackageToolSource.Scoop)
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
        PackageCatalogFile? file = JsonSerializer.Deserialize(stream, PackageCatalogJsonContext.Default.PackageCatalogFile)
            ?? throw new InvalidOperationException("Embedded package catalog deserialized to null.");
        return Build(file);
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

                if (!PackageToolSourceWire.TryParse(dto.Source, out PackageToolSource source))
                {
                    throw new InvalidOperationException(
                        $"Tool '{key}' must use winget, store, or scoop (got '{dto.Source}').");
                }

                string[] arch = dto.Architectures ?? [];
                PackageToolEntry entry = new(
                    key,
                    dto.DisplayName ?? key,
                    source,
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
                if (!WslInstallKindWire.TryParse(dto.InstallKind ?? WslInstallKindWire.Store, out WslInstallKind installKind))
                {
                    throw new InvalidOperationException(
                        $"WSL '{key}' must use fromFile or store (got '{dto.InstallKind}').");
                }

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
    PackageToolSource Source,
    string InstallId,
    IReadOnlyList<string> Architectures,
    string? ScoopBucket = null);

public sealed record WslDistroEntry(
    string ProfileToken,
    string DisplayName,
    WslInstallKind InstallKind,
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
