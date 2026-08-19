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
    public const string PoliciesFileName = "policies.json";
    public const string PackageFamilyNamesFileName = "packageFamilyNames.json";
    public const string CapabilityNamesFileName = "capabilityNames.json";
    public const string FeatureNamesFileName = "featureNames.json";
    public const string QualityPackagesDirectoryName = "quality-packages";

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
        QualityPackages = Path.Combine(Root, QualityPackagesDirectoryName);
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
    public string QualityPackages { get; }

    public static string HostPreparedMediaRoot => PreparedMediaIdentity.Root;

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
            ["qualityPackages"] = QualityPackages,
            ["incomingMediaPrefix"] = IncomingMediaPrefix,
            ["previousMediaPrefix"] = PreviousMediaPrefix,
            ["hostPreparedMediaRoot"] = HostPreparedMediaRoot,
        };

    public ApplyProgress? TryReadProgress(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(ApplyStatus))
        {
            return null;
        }

        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            // ponytail: small status file; Share ReadWrite so the elevated kernel loop can rewrite while we poll
            using FileStream stream = new(
                ApplyStatus,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            using StreamReader reader = new(stream);
            string? stage = null;
            string? log = null;
            while (reader.ReadLine() is { } line)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (line.StartsWith("stage=", StringComparison.Ordinal))
                {
                    stage = line["stage=".Length..].Trim();
                }
                else if (line.StartsWith("log=", StringComparison.Ordinal))
                {
                    log = line["log=".Length..].Trim();
                }
            }

            return stage is null ? null : new ApplyProgress(stage, string.IsNullOrWhiteSpace(log) ? null : log);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

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

public readonly record struct ApplyProgress(string Stage, string? LogPath);

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

internal sealed record PreparedMediaAuditFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("source.isoSha256")] string? SourceIsoSha256 = null,
    [property: JsonPropertyName("source.isoLength")] long? SourceIsoLength = null,
    [property: JsonPropertyName("source.index")] int? SourceIndex = null,
    [property: JsonPropertyName("mediaCache.schema")] int? MediaCacheSchema = null,
    [property: JsonPropertyName("mediaCache.key")] string? MediaCacheKey = null,
    [property: JsonPropertyName("mediaCache.entryPath")] string? MediaCacheEntryPath = null,
    [property: JsonPropertyName("mediaCache.outcome")] string? MediaCacheOutcome = null,
    [property: JsonPropertyName("mediaCache.installWimSha256")] string? MediaCacheInstallWimSha256 = null,
    [property: JsonPropertyName("mediaCache.bootWimSha256")] string? MediaCacheBootWimSha256 = null,
    [property: JsonPropertyName("mediaCache.copyMode")] string? MediaCacheCopyMode = null,
    [property: JsonPropertyName("mediaCache.recoveryAction")] string? MediaCacheRecoveryAction = null,
    [property: JsonPropertyName("mediaCache.previousMedia")] string? MediaCachePreviousMedia = null,
    [property: JsonPropertyName("timings.sourceHashMs")] int? TimingsSourceHashMs = null,
    [property: JsonPropertyName("timings.cacheValidateMs")] int? TimingsCacheValidateMs = null,
    [property: JsonPropertyName("timings.cachePrepareMs")] int? TimingsCachePrepareMs = null,
    [property: JsonPropertyName("timings.runMediaCopyMs")] int? TimingsRunMediaCopyMs = null,
    [property: JsonPropertyName("timings.mountMs")] int? TimingsMountMs = null,
    [property: JsonPropertyName("timings.exportMs")] int? TimingsExportMs = null,
    [property: JsonPropertyName("timings.buildIsoMs")] int? TimingsBuildIsoMs = null);
