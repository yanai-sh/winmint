using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

/// <summary>Apply work-directory layout. One construction site for every workdir leaf.</summary>
public sealed class ServicingWorkspace
{
    public const string LogsDirectoryName = "logs";
    public const string PayloadDirectoryName = "payload";
    public const string MediaDirectoryName = "media";
    public const string EvidenceFileName = "evidence.json";
    public const string ExpectedEvidenceFileName = "expected-evidence.json";
    public const string FailureFileName = "failure.json";
    public const string ApplyStatusFileName = "apply-status.txt";
    public const string StagesFileName = "stages.json";
    public const string WorkspaceFileName = "workspace.json";
    public const string InstallWimFileName = "install.wim";
    public const string UnattendFileName = "unattend.xml";
    public const string DigestsFileName = "digests.json";
    public const string PreparedMediaFileName = "prepared-media.json";
    public const string IncomingMediaPrefix = "media.incoming-";
    public const string PreviousMediaPrefix = "media.previous-";

    public ServicingWorkspace(string root)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        Root = Path.GetFullPath(root);
        Logs = Path.Combine(Root, LogsDirectoryName);
        Payload = Path.Combine(Root, PayloadDirectoryName);
        Media = Path.Combine(Root, MediaDirectoryName);
        Evidence = Path.Combine(Root, EvidenceFileName);
        ExpectedEvidence = Path.Combine(Root, ExpectedEvidenceFileName);
        Failure = Path.Combine(Root, FailureFileName);
        ApplyStatus = Path.Combine(Root, ApplyStatusFileName);
        Stages = Path.Combine(Root, StagesFileName);
        WorkspaceManifest = Path.Combine(Root, WorkspaceFileName);
        InstallWim = Path.Combine(Root, InstallWimFileName);
        Unattend = Path.Combine(Root, UnattendFileName);
        Digests = Path.Combine(Logs, DigestsFileName);
        PreparedMedia = Path.Combine(Root, PreparedMediaFileName);
    }

    public string Root { get; }
    public string Logs { get; }
    public string Payload { get; }
    public string Media { get; }
    public string Evidence { get; }
    public string ExpectedEvidence { get; }
    public string Failure { get; }
    public string ApplyStatus { get; }
    public string Stages { get; }
    public string WorkspaceManifest { get; }
    public string InstallWim { get; }
    public string Unattend { get; }
    public string Digests { get; }
    public string PreparedMedia { get; }

    public static string HostPreparedMediaRoot => MediaCacheIdentity.Root;

    public IReadOnlyDictionary<string, string> LeafMap() =>
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["root"] = Root,
            ["logs"] = Logs,
            ["payload"] = Payload,
            ["media"] = Media,
            ["evidence"] = Evidence,
            ["expectedEvidence"] = ExpectedEvidence,
            ["failure"] = Failure,
            ["applyStatus"] = ApplyStatus,
            ["stages"] = Stages,
            ["installWim"] = InstallWim,
            ["unattend"] = Unattend,
            ["digests"] = Digests,
            ["preparedMedia"] = PreparedMedia,
            ["incomingMediaPrefix"] = IncomingMediaPrefix,
            ["previousMediaPrefix"] = PreviousMediaPrefix,
            ["hostPreparedMediaRoot"] = HostPreparedMediaRoot,
        };

    public void WriteManifest()
    {
        Directory.CreateDirectory(Root);
        File.WriteAllBytes(
            WorkspaceManifest,
            JsonSerializer.SerializeToUtf8Bytes(
                new Dictionary<string, string>(LeafMap(), StringComparer.Ordinal),
                ServicingJsonContext.Default.DictionaryStringString));
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
    string? ImageBuild = null)
{
    public Dictionary<string, string> ToStageBag()
    {
        Dictionary<string, string> bag = new(StringComparer.Ordinal)
        {
            [StageParams.SourceIso] = SourceIso,
            [StageParams.MountDir] = MountDir,
            [StageParams.MediaDir] = MediaDir,
            [StageParams.WimIndex] = WimIndex.ToString(System.Globalization.CultureInfo.InvariantCulture),
            [StageParams.WorkDirectory] = WorkDirectory,
            [StageParams.SourceIsoSha256] = SourceIsoSha256,
            [StageParams.SourceIsoLength] = SourceIsoLength.ToString(System.Globalization.CultureInfo.InvariantCulture),
            [StageParams.CacheSchema] = CacheSchema.ToString(System.Globalization.CultureInfo.InvariantCulture),
            [StageParams.CacheRoot] = CacheRoot,
        };
        if (!string.IsNullOrWhiteSpace(ImageName))
        {
            bag[StageParams.ImageName] = ImageName;
        }

        if (!string.IsNullOrWhiteSpace(Architecture))
        {
            bag[StageParams.Architecture] = Architecture;
        }

        if (!string.IsNullOrWhiteSpace(ImageEdition))
        {
            bag[StageParams.ImageEdition] = ImageEdition;
        }

        if (!string.IsNullOrWhiteSpace(ImageBuild))
        {
            bag[StageParams.ImageBuild] = ImageBuild;
        }

        return bag;
    }
}

internal sealed record ExpectedEvidenceFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("lane")] string Lane,
    [property: JsonPropertyName("packageStrict")] bool PackageStrict,
    [property: JsonPropertyName("expectDrivers")] bool ExpectDrivers,
    [property: JsonPropertyName("expectFuPosture")] bool ExpectFuPosture,
    [property: JsonPropertyName("requiredDigestKeys")] IReadOnlyList<string> RequiredDigestKeys,
    [property: JsonPropertyName("requiredDigestValues")] Dictionary<string, string> RequiredDigestValues,
    [property: JsonPropertyName("requiredJobKinds")] IReadOnlyList<string> RequiredJobKinds,
    [property: JsonPropertyName("requiredWingetIds")] IReadOnlyList<string> RequiredWingetIds);
