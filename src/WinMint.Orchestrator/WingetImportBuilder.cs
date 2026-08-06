using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>Build winget export/import JSON from Profile winget ids + catalog ([alpha package program spec]).</summary>
public static class WingetImportBuilder
{
    private const string Schema = "https://aka.ms/winget-packages.schema.2.0.json";

    public static byte[] BuildUtf8Json(
        IReadOnlyList<string> wingetInstallIds,
        PackageCatalog catalog,
        string imageArchitecture)
    {
        List<WingetImportPackageDto> packages = [];
        foreach (string installId in wingetInstallIds)
        {
            if (!catalog.TryGetToolByInstallId(installId, out PackageToolEntry? tool))
            {
                continue;
            }

            string? archFlag = PackageCatalog.ResolveWingetArchitectureFlag(tool, imageArchitecture);
            packages.Add(new WingetImportPackageDto(
                installId,
                string.IsNullOrWhiteSpace(archFlag) ? null : $"--architecture {archFlag}"));
        }

        if (packages.Count == 0)
        {
            return [];
        }

        WingetImportFile file = new(
            Schema,
            DateTimeOffset.UtcNow,
            [
                new WingetImportSourceDto(
                    new WingetSourceDetailsDto(
                        "winget",
                        "8wekyb3d8bbwe",
                        "https://cdn.winget.microsoft.com/cache",
                        "Microsoft.PreIndexed.Package"),
                    packages),
            ]);

        return JsonSerializer.SerializeToUtf8Bytes(file, WingetImportJsonContext.Default.WingetImportFile);
    }
}

internal sealed record WingetImportFile(
    [property: JsonPropertyName("$schema")] string Schema,
    [property: JsonPropertyName("CreationDate")] DateTimeOffset CreationDate,
    [property: JsonPropertyName("Sources")] WingetImportSourceDto[] Sources);

internal sealed record WingetImportSourceDto(
    [property: JsonPropertyName("SourceDetails")] WingetSourceDetailsDto SourceDetails,
    [property: JsonPropertyName("Packages")] IReadOnlyList<WingetImportPackageDto> Packages);

internal sealed record WingetSourceDetailsDto(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Identifier")] string Identifier,
    [property: JsonPropertyName("Argument")] string Argument,
    [property: JsonPropertyName("Type")] string Type);

internal sealed record WingetImportPackageDto(
    [property: JsonPropertyName("PackageIdentifier")] string PackageIdentifier,
    [property: JsonPropertyName("InitialOverrideArguments")] string? InitialOverrideArguments);

[JsonSerializable(typeof(WingetImportFile))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, WriteIndented = true)]
internal sealed partial class WingetImportJsonContext : JsonSerializerContext;
