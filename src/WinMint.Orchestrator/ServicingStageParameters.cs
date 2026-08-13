using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization.Metadata;

namespace WinMint.Orchestrator;

internal static class StageParamJson
{
    public static JsonObject From<T>(T record, JsonTypeInfo<T> typeInfo) =>
        JsonSerializer.SerializeToNode(record, typeInfo)!.AsObject();

    public static Dictionary<string, string> ToBag(JsonObject obj)
    {
        Dictionary<string, string> bag = new(StringComparer.Ordinal);
        foreach (KeyValuePair<string, JsonNode?> p in obj)
        {
            bag[p.Key] = p.Value is null || p.Value.GetValueKind() is JsonValueKind.Null or JsonValueKind.Undefined
                ? ""
                : p.Value.GetValueKind() == JsonValueKind.String
                    ? p.Value.GetValue<string>() ?? ""
                    : p.Value.ToJsonString();
        }

        return bag;
    }
}

/// <summary>Typed MountInstallWim parameters. CacheSchema/CacheRoot are the Prepared-media store (kernel names, not a product cache). No reuseMedia.</summary>
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
