using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

internal sealed record PackagesProofEntry(string Source, string Id, string? ScoopBucket);

public static partial class PackagesProof
{
    internal const string SchemaVersion = "winmint.packages.proof/v1";
    internal const string DefaultArchitecture = "arm64";

    internal static string CatalogSha256(string catalogPath)
    {
        byte[] bytes = File.ReadAllBytes(catalogPath);
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    internal static IReadOnlyList<string> MissingProductConstants(PackageCatalog catalog)
    {
        List<string> missing = [];
        foreach (string id in ProductPosture.WingetIds)
        {
            if (!catalog.TryGetToolByInstallId(id, out PackageToolEntry? tool)
                || tool.Source is not PackageToolSource.Winget
                || tool.IsStub)
            {
                missing.Add($"winget:{id}");
            }
        }

        foreach (string id in ProductPosture.ScoopIds)
        {
            if (!catalog.TryGetToolByInstallId(id, out PackageToolEntry? tool)
                || tool.Source is not PackageToolSource.Scoop
                || tool.IsStub)
            {
                missing.Add($"scoop:{id}");
            }
        }

        return missing;
    }

    internal static IReadOnlyList<PackagesProofEntry> BuildProveSet(
        PackageCatalog catalog,
        string architecture)
    {
        string arch = PackageCatalog.NormalizeArch(architecture);
        List<PackagesProofEntry> list = [];
        foreach (string key in catalog.ToolCatalogKeys)
        {
            if (!catalog.TryGetToolByKey(key, out PackageToolEntry? tool) || tool.IsStub)
            {
                continue;
            }

            if (tool.Architectures.Count == 0
                || !tool.Architectures.Any(a => string.Equals(a, arch, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            if (tool.Source is PackageToolSource.Winget)
            {
                list.Add(new PackagesProofEntry("winget", tool.InstallId, null));
            }
            else if (tool.Source is PackageToolSource.Scoop)
            {
                list.Add(new PackagesProofEntry(
                    "scoop",
                    tool.InstallId,
                    tool.ScoopBucket ?? "main"));
            }
            // store / other: skip
        }

        return list
            .OrderBy(e => e.Source, StringComparer.Ordinal)
            .ThenBy(e => e.Id, StringComparer.Ordinal)
            .ToArray();
    }

    internal static string ProveSetSha256(IReadOnlyList<PackagesProofEntry> entries)
    {
        IOrderedEnumerable<PackagesProofEntry> ordered = entries
            .OrderBy(e => e.Source, StringComparer.Ordinal)
            .ThenBy(e => e.Id, StringComparer.Ordinal);
        StringBuilder sb = new();
        foreach (PackagesProofEntry e in ordered)
        {
            sb.Append(e.Source).Append(':').Append(e.Id).Append('\n');
        }

        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString())))
            .ToLowerInvariant();
    }

    public static IReadOnlyList<string> Validate(
        string proofPath,
        string catalogPath,
        PackageCatalog catalog,
        string architecture)
    {
        List<string> errors = [];
        foreach (string m in MissingProductConstants(catalog))
        {
            errors.Add($"product constant missing or stub in catalog: {m}");
        }

        if (!File.Exists(proofPath))
        {
            errors.Add("Missing config/packages.proof.json — run: just packages-check");
            return errors;
        }

        PackagesProofFile? doc;
        try
        {
            doc = JsonSerializer.Deserialize(
                File.ReadAllBytes(proofPath),
                PackagesProofJsonContext.Default.PackagesProofFile);
        }
        catch (Exception ex)
        {
            errors.Add($"packages.proof.json parse failed: {ex.Message}");
            return errors;
        }

        if (doc is null || !string.Equals(doc.SchemaVersion, SchemaVersion, StringComparison.Ordinal))
        {
            errors.Add($"packages.proof.json schemaVersion must be {SchemaVersion}");
        }

        string arch = PackageCatalog.NormalizeArch(architecture);
        if (!string.Equals(doc?.Architecture, arch, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add($"packages.proof.json architecture must be {arch}");
        }

        string catalogHash = CatalogSha256(catalogPath);
        if (!string.Equals(doc?.CatalogSha256, catalogHash, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("catalogSha256 mismatch — run: just packages-check");
        }

        IReadOnlyList<PackagesProofEntry> proveSet = BuildProveSet(catalog, arch);
        foreach (string duplicate in DuplicateIdentities(proveSet))
        {
            errors.Add($"catalog prove set has duplicate identity {duplicate}");
        }

        string proveHash = ProveSetSha256(proveSet);
        if (!string.Equals(doc?.ProveSetSha256, proveHash, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("proveSetSha256 mismatch — run: just packages-check");
        }

        if (doc?.ProvenAtUtc is null
            || doc.ProvenAtUtc == default
            || doc.ProvenAtUtc.Value.Offset != TimeSpan.Zero)
        {
            errors.Add("packages.proof.json provenAtUtc must be a valid UTC timestamp");
        }

        PackagesProofHostFile? host = doc?.Host;
        if (host is null
            || !string.Equals(host.OsArchitecture, "Arm64", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(host.ProcessArchitecture, "Arm64", StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("packages.proof.json host must attest native Arm64 OS and process architecture");
        }

        if (host is null
            || !string.Equals(host.ProcessorArchitecture, "ARM64", StringComparison.OrdinalIgnoreCase)
            || !host.ProcessorArchitectureW6432Present
            || (!string.IsNullOrWhiteSpace(host.ProcessorArchitectureW6432)
                && !string.Equals(
                    host.ProcessorArchitectureW6432,
                    "ARM64",
                    StringComparison.OrdinalIgnoreCase)))
        {
            errors.Add(
                "packages.proof.json host environment diagnostics are missing or inconsistent with native ARM64");
        }

        if (string.IsNullOrWhiteSpace(host?.WingetVersion))
        {
            errors.Add("packages.proof.json host wingetVersion is required");
        }

        List<PackagesProofEntryFile?> actualEntries = doc?.Entries ?? [];
        if (actualEntries.Count != proveSet.Count)
        {
            errors.Add(
                $"proof entries count must be exactly {proveSet.Count} (got {actualEntries.Count}) — run: just packages-check");
        }

        int comparableCount = Math.Min(actualEntries.Count, proveSet.Count);
        for (int i = 0; i < comparableCount; i++)
        {
            PackagesProofEntry required = proveSet[i];
            PackagesProofEntryFile? actual = actualEntries[i];
            string key = $"{required.Source}:{required.Id}";
            string expectedMethod = ExpectedMethod(required.Source);
            if (actual is null
                || string.IsNullOrWhiteSpace(actual.Source)
                || string.IsNullOrWhiteSpace(actual.Id))
            {
                errors.Add($"proof entry {i} is malformed — run: just packages-check");
                continue;
            }

            if (!string.Equals(actual.Source, required.Source, StringComparison.Ordinal)
                || !string.Equals(actual.Id, required.Id, StringComparison.Ordinal))
            {
                errors.Add(
                    $"proof entry {i} must be {key} (got {actual.Source}:{actual.Id}) — run: just packages-check");
            }

            if (!string.Equals(actual.Bucket, required.ScoopBucket, StringComparison.Ordinal))
            {
                errors.Add($"proof entry {key} has wrong bucket — run: just packages-check");
            }

            if (!string.Equals(actual.Method, expectedMethod, StringComparison.Ordinal))
            {
                errors.Add(
                    $"proof entry {key} method must be {expectedMethod} — run: just packages-check");
            }
        }

        return errors;
    }

    internal static string ExpectedMethod(string source) => source switch
    {
        "winget" => "winget-download",
        "scoop" => "scoop-manifest-download",
        _ => throw new InvalidOperationException($"Unsupported proof source '{source}'."),
    };

    internal static IReadOnlyList<string> DuplicateIdentities(
        IEnumerable<PackagesProofEntry> entries) =>
        entries
            .GroupBy(e => $"{e.Source}:{e.Id}", StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Skip(1).Any())
            .Select(group => group.Key)
            .Order(StringComparer.Ordinal)
            .ToArray();
}

internal sealed class PackagesProofFile
{
    [JsonPropertyName("schemaVersion")]
    public string? SchemaVersion { get; set; }

    [JsonPropertyName("architecture")]
    public string? Architecture { get; set; }

    [JsonPropertyName("catalogSha256")]
    public string? CatalogSha256 { get; set; }

    [JsonPropertyName("proveSetSha256")]
    public string? ProveSetSha256 { get; set; }

    [JsonPropertyName("provenAtUtc")]
    public DateTimeOffset? ProvenAtUtc { get; set; }

    [JsonPropertyName("host")]
    public PackagesProofHostFile? Host { get; set; }

    [JsonPropertyName("entries")]
    public List<PackagesProofEntryFile?>? Entries { get; set; }
}

internal sealed class PackagesProofEntryFile
{
    [JsonPropertyName("source")]
    public string? Source { get; set; }

    [JsonPropertyName("id")]
    public string? Id { get; set; }

    [JsonPropertyName("method")]
    public string? Method { get; set; }

    [JsonPropertyName("bucket")]
    public string? Bucket { get; set; }
}

internal sealed class PackagesProofHostFile
{
    private string? _processorArchitectureW6432;

    [JsonPropertyName("osArchitecture")]
    public string? OsArchitecture { get; set; }

    [JsonPropertyName("processArchitecture")]
    public string? ProcessArchitecture { get; set; }

    [JsonPropertyName("processorArchitecture")]
    public string? ProcessorArchitecture { get; set; }

    [JsonPropertyName("processorArchitectureW6432")]
    public string? ProcessorArchitectureW6432
    {
        get => _processorArchitectureW6432;
        set
        {
            _processorArchitectureW6432 = value;
            ProcessorArchitectureW6432Present = true;
        }
    }

    [JsonIgnore]
    public bool ProcessorArchitectureW6432Present { get; private set; }

    [JsonPropertyName("wingetVersion")]
    public string? WingetVersion { get; set; }
}

[JsonSerializable(typeof(PackagesProofFile))]
[JsonSerializable(typeof(PackagesCheckRequestFile))]
[JsonSerializable(typeof(PackagesCheckOutcomeFile))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PackagesProofJsonContext : JsonSerializerContext;
