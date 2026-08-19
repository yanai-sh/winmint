using System.Collections.Frozen;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class ImageServicing
{
    private static Result<ImageEvidence, Failure> WriteEvidence(
        ServicingWorkspace workspace,
        BuildArtifacts plan,
        ServicingRun run,
        IReadOnlyList<ServicingStage> stages)
    {
        if (!File.Exists(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.outputIso.missing", "BuildIso output missing."));
        }

        if (!stages.Any(static s => s.Opcode == ServicingOpcode.StampOfflineShell))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.shellStamp.missing",
                    "StampOfflineShell stage missing or incomplete."));
        }

        if (!stages.Any(static s => s.Opcode == ServicingOpcode.ExportWim))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.lane.missing", "ExportWim stage missing lane."));
        }

        string shellTarget = ShellStampGuestPath;
        string plannedLane = plan.Manifest.ImageQuality.ToString();

        if (!File.Exists(workspace.Digests))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.digests.missing", "logs/digests.json missing."));
        }

        Dictionary<string, string>? digests;
        try
        {
            digests = JsonSerializer.Deserialize(
                File.ReadAllBytes(workspace.Digests),
                ServicingJsonContext.Default.DictionaryStringString);
        }
        catch (JsonException ex)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.invalid", ex.Message));
        }

        if (digests is null
            || !digests.TryGetValue("outputIso.sha256", out string? outputIsoSha)
            || string.IsNullOrWhiteSpace(outputIsoSha))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.digests.outputIso",
                    "logs/digests.json missing outputIso.sha256."));
        }

        JsonObject doc = new()
        {
            ["schemaVersion"] = EvidenceSchemaVersion,
            ["outputIsoPath"] = run.OutputIsoPath,
            ["shellStampTargetPath"] = shellTarget,
            ["lane"] = plannedLane,
            ["packageStrict"] = plan.PackageStrict,
        };
        JsonObject digestNode = new();
        foreach (KeyValuePair<string, string> kv in digests)
        {
            digestNode[kv.Key] = kv.Value;
        }

        doc["digests"] = digestNode;

        IReadOnlyDictionary<string, string> preparedFields =
            FrozenDictionary<string, string>.Empty;
        if (File.Exists(workspace.PreparedMedia))
        {
            PreparedMediaAuditFile? audit;
            try
            {
                audit = JsonSerializer.Deserialize(
                    File.ReadAllBytes(workspace.PreparedMedia),
                    ServicingJsonContext.Default.PreparedMediaAuditFile);
            }
            catch (JsonException ex)
            {
                return Result.Fail<ImageEvidence, Failure>(
                    new Failure("servicing.evidence.preparedMedia.invalid", ex.Message));
            }

            if (audit is null
                || !string.Equals(audit.SchemaVersion, PreparedMediaAuditSchemaVersion, StringComparison.Ordinal))
            {
                return Result.Fail<ImageEvidence, Failure>(
                    new Failure(
                        "servicing.evidence.preparedMedia.schema",
                        $"prepared-media.json schema '{audit?.SchemaVersion}' (need {PreparedMediaAuditSchemaVersion})."));
            }

            Dictionary<string, string> fields = [];
            CopyPreparedMediaAudit(doc, audit, fields);
            preparedFields = fields.ToFrozenDictionary(StringComparer.Ordinal);
        }

        File.WriteAllText(workspace.Evidence, doc.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

        return Result.Ok<ImageEvidence, Failure>(
            new ImageEvidence(
                run.OutputIsoPath,
                plan.Manifest.ImageQuality,
                shellTarget,
                digests.ToFrozenDictionary(StringComparer.Ordinal),
                preparedFields));
    }

    private static void CopyPreparedMediaAudit(
        JsonObject doc,
        PreparedMediaAuditFile audit,
        Dictionary<string, string> preparedFields)
    {
        SetIfPresent(doc, preparedFields, "source.isoSha256", audit.SourceIsoSha256);
        if (audit.SourceIsoLength is long length)
        {
            doc["source.isoLength"] = length;
        }

        if (audit.SourceIndex is int index)
        {
            doc["source.index"] = index;
        }

        if (audit.MediaCacheSchema is int schema)
        {
            doc["mediaCache.schema"] = schema;
        }

        SetIfPresent(doc, preparedFields, "mediaCache.key", audit.MediaCacheKey);
        SetIfPresent(doc, preparedFields, "mediaCache.entryPath", audit.MediaCacheEntryPath);
        SetIfPresent(doc, preparedFields, "mediaCache.outcome", audit.MediaCacheOutcome);
        SetIfPresent(doc, preparedFields, "mediaCache.installWimSha256", audit.MediaCacheInstallWimSha256);
        SetIfPresent(doc, preparedFields, "mediaCache.bootWimSha256", audit.MediaCacheBootWimSha256);
        SetIfPresent(doc, preparedFields, "mediaCache.copyMode", audit.MediaCacheCopyMode);
        SetIfPresent(doc, preparedFields, "mediaCache.recoveryAction", audit.MediaCacheRecoveryAction);
        SetTiming(doc, "timings.sourceHashMs", audit.TimingsSourceHashMs);
        SetTiming(doc, "timings.cacheValidateMs", audit.TimingsCacheValidateMs);
        SetTiming(doc, "timings.cachePrepareMs", audit.TimingsCachePrepareMs);
        SetTiming(doc, "timings.runMediaCopyMs", audit.TimingsRunMediaCopyMs);
        SetTiming(doc, "timings.mountMs", audit.TimingsMountMs);
        SetTiming(doc, "timings.exportMs", audit.TimingsExportMs);
        SetTiming(doc, "timings.buildIsoMs", audit.TimingsBuildIsoMs);
    }

    private static void SetIfPresent(
        JsonObject doc,
        Dictionary<string, string> preparedFields,
        string key,
        string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            doc[key] = value;
            preparedFields[key] = value;
        }
    }

    private static void SetTiming(JsonObject doc, string key, int? value)
    {
        if (value is int ms)
        {
            doc[key] = ms;
        }
    }

    private static void WriteExpectedEvidence(
        ServicingWorkspace workspace,
        BuildArtifacts plan,
        IReadOnlyList<ServicingStage> stages)
    {
        bool injectDrivers = stages.Any(static s => s.Opcode == ServicingOpcode.InjectDrivers);
        bool expectFu = plan.Manifest.ImageQuality == ImageQualityLane.Release;
        IReadOnlyList<OfflinePolicyRow> rows = plan.OfflinePolicies;
        Dictionary<string, string> requiredValues = new(StringComparer.Ordinal);
        List<string> requiredKeys = ["outputIso.sha256"];
        foreach (OfflinePolicyRow row in rows)
        {
            requiredKeys.Add(row.Digest);
            requiredValues[row.Digest] = row.Data;
        }

        if (injectDrivers)
        {
            requiredKeys.AddRange(["drivers.deviceId", "drivers.includedCount", "drivers.excludedCount"]);
        }

        HashSet<string> needed =
        [
            ProvisionJobKindWire.WingetImport,
            ProvisionJobKindWire.ScoopBatch,
            ProvisionJobKindWire.ShellStamp,
            ProvisionJobKindWire.PackageAuditNative,
        ];
        List<string> requiredJobs = [.. plan.Jobs.Jobs
            .Select(static j => j.Kind.ToWire())
            .Where(needed.Contains)
            .Distinct(StringComparer.Ordinal)];

        List<string> wingetIds = plan.WingetImportJson is { Length: > 0 }
            ? [.. ProductPosture.WingetIds]
            : [];

        ExpectedEvidenceFile expected = new(
            ExpectedEvidenceSchemaVersion,
            plan.Manifest.ImageQuality.ToString(),
            plan.PackageStrict,
            injectDrivers,
            expectFu,
            [.. requiredKeys.Distinct(StringComparer.Ordinal)],
            requiredValues,
            [.. requiredJobs],
            wingetIds);
        File.WriteAllBytes(
            workspace.ExpectedEvidence,
            JsonSerializer.SerializeToUtf8Bytes(expected, ServicingJsonContext.Default.ExpectedEvidenceFile));
    }
}

internal sealed record FailureFile(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("message")] string? Message,
    [property: JsonPropertyName("opcode")] string? Opcode);

[JsonSerializable(typeof(ExpectedEvidenceFile))]
[JsonSerializable(typeof(PreparedMediaAuditFile))]
[JsonSerializable(typeof(FailureFile))]
[JsonSerializable(typeof(Dictionary<string, string>))]
[JsonSerializable(typeof(OfflinePolicyRow[]))]
[JsonSerializable(typeof(string[]))]
[JsonSerializable(typeof(MountInstallWimParameters))]
[JsonSerializable(typeof(StagePayloadParameters))]
[JsonSerializable(typeof(StageOobeUnattendParameters))]
[JsonSerializable(typeof(PatchBootWimApplyParameters))]
[JsonSerializable(typeof(AddQualityUpdatesParameters))]
[JsonSerializable(typeof(StampOfflineShellParameters))]
[JsonSerializable(typeof(StampOfflinePoliciesParameters))]
[JsonSerializable(typeof(RemoveProvisionedAppxParameters))]
[JsonSerializable(typeof(RemoveCapabilitiesParameters))]
[JsonSerializable(typeof(DisableOptionalFeaturesParameters))]
[JsonSerializable(typeof(InjectDriversParameters))]
[JsonSerializable(typeof(ExportWimParameters))]
[JsonSerializable(typeof(BuildIsoParameters))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ServicingJsonContext : JsonSerializerContext;
