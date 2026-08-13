using System.Text.Json;
using System.Text.Json.Serialization.Metadata;

namespace WinMint.Orchestrator;

/// <summary>Flatten a typed opcode record through <see cref="ServicingJsonContext"/> into the stages.json bag.</summary>
internal static class StageParamBag
{
    // ponytail: JSON flatten to string bag; nested/non-scalar properties would need a real typed stages.json.
    public static Dictionary<string, string> From<T>(T record, JsonTypeInfo<T> typeInfo)
    {
        using JsonDocument doc = JsonDocument.Parse(JsonSerializer.SerializeToUtf8Bytes(record, typeInfo));
        Dictionary<string, string> bag = new(StringComparer.Ordinal);
        foreach (JsonProperty p in doc.RootElement.EnumerateObject())
        {
            bag[p.Name] = p.Value.ValueKind switch
            {
                JsonValueKind.Null or JsonValueKind.Undefined => "",
                JsonValueKind.String => p.Value.GetString() ?? "",
                _ => p.Value.GetRawText(),
            };
        }

        return bag;
    }
}

/// <summary>Typed MountInstallWim bag (post-cache). No reuseMedia.</summary>
public sealed record MountInstallWimParameters(
    string SourceIso,
    string MountDir,
    string MediaDir,
    int WimIndex,
    string WorkDirectory,
    string SourceIsoSha256,
    long SourceIsoLength,
    int CacheSchema,
    string CacheRoot,
    string? ImageName = null,
    string? Architecture = null,
    string? ImageEdition = null,
    string? ImageBuild = null);

public sealed record StagePayloadParameters(string PayloadDir, string MountDir);

public sealed record StageOobeUnattendParameters(string UnattendPath, string MountDir, string MediaDir);

public sealed record PatchBootWimApplyParameters(string MediaDir, string MountDir, string WorkDirectory);

public sealed record StampOfflineShellParameters(string ShellTarget, string MountDir);

public sealed record StampOfflinePoliciesParameters(string MountDir, string WorkDirectory, string PoliciesPath);

public sealed record RemoveProvisionedAppxParameters(
    string MountDir,
    string WorkDirectory,
    string PackageFamilyNamesPath);

public sealed record RemoveCapabilitiesParameters(
    string MountDir,
    string WorkDirectory,
    string Kind,
    string NamesPath);

public sealed record DisableOptionalFeaturesParameters(
    string MountDir,
    string WorkDirectory,
    string Kind,
    string NamesPath);

public sealed record InjectDriversParameters(
    string MountDir,
    string WorkDirectory,
    string MediaDir,
    string DeviceId,
    string DetailsUrl,
    string ExpectedFileNameRegex);

public sealed record ExportWimParameters(
    string MountDir,
    string MediaDir,
    string WimOut,
    string WorkDirectory,
    string Lane,
    string Compression,
    string Cleanup);

public sealed record BuildIsoParameters(string OutputIso, string MediaDir);
