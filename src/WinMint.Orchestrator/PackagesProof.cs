using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public sealed record PackagesProofEntry(string Source, string Id, string? ScoopBucket);

public static class PackagesProof
{
    public const string SchemaVersion = "winmint.packages.proof/v1";
    public const string DefaultArchitecture = "arm64";

    public static string CatalogSha256(string catalogPath)
    {
        byte[] bytes = File.ReadAllBytes(catalogPath);
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    public static IReadOnlyList<string> MissingProductConstants(PackageCatalog catalog)
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

    public static IReadOnlyList<PackagesProofEntry> BuildProveSet(
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

            if (tool.Architectures.Count > 0
                && !tool.Architectures.Any(a => string.Equals(a, arch, StringComparison.OrdinalIgnoreCase)))
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

    public static string ProveSetSha256(IReadOnlyList<PackagesProofEntry> entries)
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
        string proveHash = ProveSetSha256(proveSet);
        if (!string.Equals(doc?.ProveSetSha256, proveHash, StringComparison.OrdinalIgnoreCase))
        {
            errors.Add("proveSetSha256 mismatch — run: just packages-check");
        }

        HashSet<string> provenIds = new(StringComparer.OrdinalIgnoreCase);
        foreach (PackagesProofEntryFile? e in doc?.Entries ?? [])
        {
            if (e?.Source is null || e.Id is null)
            {
                continue;
            }

            provenIds.Add($"{e.Source.ToLowerInvariant()}:{e.Id}");
        }

        foreach (PackagesProofEntry required in proveSet)
        {
            string key = $"{required.Source}:{required.Id}";
            if (!provenIds.Contains(key))
            {
                errors.Add($"proof missing entry {key} — run: just packages-check");
            }
        }

        return errors;
    }
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

    [JsonPropertyName("entries")]
    public List<PackagesProofEntryFile>? Entries { get; set; }
}

internal sealed class PackagesProofEntryFile
{
    [JsonPropertyName("source")]
    public string? Source { get; set; }

    [JsonPropertyName("id")]
    public string? Id { get; set; }
}

[JsonSerializable(typeof(PackagesProofFile))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PackagesProofJsonContext : JsonSerializerContext;
