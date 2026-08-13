using System.Collections.Frozen;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public const string EvidenceSchemaVersion = "winmint.image.evidence/v1";
    public const string ExpectedEvidenceSchemaVersion = "winmint.expected-evidence/v1";
    public const string ServicingStagesSchemaVersion = "winmint.servicing.stages/v1";
    public const string PreparedMediaAuditSchemaVersion = "winmint.prepared-media.audit/v1";
    public const string BundleSchemaVersion = GuestBundleWire.SchemaVersion;

    /// <summary>Guest path stamped into Winlogon Shell (offline); Machine setup verifies the same path.</summary>
    public const string ShellStampGuestPath = @"C:\Windows\WinMint\Supervisor.exe";

    /// <summary>
    /// Host-only DISM mount root (not guest durable state). Keeps mounts off workdir/.scratch trees —
    /// short path, single cleanup locus. Subdirs: mount, boot-mount.
    /// </summary>
    public static string HostServicingRoot { get; } =
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "WinMint",
            "Servicing");

    public static string HostMountDir => Path.Combine(HostServicingRoot, "mount");

    public static string HostBootMountDir => Path.Combine(HostServicingRoot, "boot-mount");

    /// <summary>Smoke default: Windows 11 Pro on consumer multi-edition ARM64/x64 ISOs (Home=1, Home SL=2, Pro=3).
    /// MountInstallWim exports this index to a single-image WIM before mount (IMAGESERVICING invariant 8).</summary>
    public const int DefaultProWimIndex = 3;

    /// <summary>Materialize stages and run elevated ImageServicing against a Source ISO (default pwsh runner).</summary>
    public static Task<Result<ImageEvidence, Failure>> ApplyAsync(
        BuildArtifacts plan,
        ServicingRun run,
        CancellationToken ct = default) =>
        ApplyAsync(plan, run, new PwshElevatedPlanRunner(), ct);

    /// <summary>Materialize stages and run elevated ImageServicing against a Source ISO.</summary>
    public static async Task<Result<ImageEvidence, Failure>> ApplyAsync(
        BuildArtifacts plan,
        ServicingRun run,
        IElevatedPlanRunner runner,
        CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(plan);
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(runner);

        if (string.IsNullOrWhiteSpace(run.WorkDirectory))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.workdir.missing", "WorkDirectory is required."));
        }

        if (string.IsNullOrWhiteSpace(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.outputIso.missing",
                    "OutputIsoPath is required. HostCompile freezes the Output ISO path before Apply."));
        }

        if (string.IsNullOrWhiteSpace(run.SourceIsoPath) || !File.Exists(run.SourceIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.sourceIso.missing", $"Source ISO not found: {run.SourceIsoPath}"));
        }

        ServicingRun normalized = run with { OutputIsoPath = run.OutputIsoPath.Trim() };

        ServicingWorkspace workspace = new(normalized.WorkDirectory);
        Directory.CreateDirectory(workspace.Root);
        Directory.CreateDirectory(workspace.Logs);
        Directory.CreateDirectory(HostServicingRoot);

        Result<IReadOnlyList<ServicingStage>, Failure> materialized = Materialize(plan, normalized, workspace);
        if (!materialized.IsOk)
        {
            return Result.Fail<ImageEvidence, Failure>(materialized.Error);
        }

        // Materialize already wrote stages.json; that file is the seam (Invoke-ServicingPlan.ps1 reads it).
        Result<ElevatedRunOk, Failure> elevated = await runner.ExecuteAsync(workspace, ct)
            .ConfigureAwait(false);
        if (!elevated.IsOk)
        {
            // Invariant: never delete workdir on failure (or success) — caller owns lifetime.
            return Result.Fail<ImageEvidence, Failure>(elevated.Error);
        }

        return WriteEvidence(workspace, plan, normalized, materialized.Value);
    }

    public static string SerializeServicingStagesFile(
        IReadOnlyList<(ServicingOpcode Opcode, JsonObject Parameters)> stages)
    {
        JsonArray arr = [];
        foreach ((ServicingOpcode opcode, JsonObject parameters) in stages)
        {
            JsonNode stage = new JsonObject
            {
                ["opcode"] = opcode.ToString(),
                ["parameters"] = parameters.DeepClone(),
            };
            arr.Add(stage);
        }

        JsonObject doc = new()
        {
            ["schemaVersion"] = ServicingStagesSchemaVersion,
            ["stages"] = arr,
        };
        return doc.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

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

            CopyPreparedMediaAudit(doc, audit);
        }

        File.WriteAllText(workspace.Evidence, doc.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

        return Result.Ok<ImageEvidence, Failure>(
            new ImageEvidence(
                run.OutputIsoPath,
                plan.Manifest.ImageQuality,
                shellTarget,
                digests.ToFrozenDictionary(StringComparer.Ordinal)));
    }

    private static void CopyPreparedMediaAudit(JsonObject doc, PreparedMediaAuditFile audit)
    {
        SetIfPresent(doc, "source.isoSha256", audit.SourceIsoSha256);
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

        SetIfPresent(doc, "mediaCache.key", audit.MediaCacheKey);
        SetIfPresent(doc, "mediaCache.entryPath", audit.MediaCacheEntryPath);
        SetIfPresent(doc, "mediaCache.outcome", audit.MediaCacheOutcome);
        SetIfPresent(doc, "mediaCache.installWimSha256", audit.MediaCacheInstallWimSha256);
        SetIfPresent(doc, "mediaCache.bootWimSha256", audit.MediaCacheBootWimSha256);
        SetIfPresent(doc, "mediaCache.copyMode", audit.MediaCacheCopyMode);
        SetIfPresent(doc, "mediaCache.recoveryAction", audit.MediaCacheRecoveryAction);
        SetTiming(doc, "timings.sourceHashMs", audit.TimingsSourceHashMs);
        SetTiming(doc, "timings.cacheValidateMs", audit.TimingsCacheValidateMs);
        SetTiming(doc, "timings.cachePrepareMs", audit.TimingsCachePrepareMs);
        SetTiming(doc, "timings.runMediaCopyMs", audit.TimingsRunMediaCopyMs);
        SetTiming(doc, "timings.mountMs", audit.TimingsMountMs);
        SetTiming(doc, "timings.exportMs", audit.TimingsExportMs);
        SetTiming(doc, "timings.buildIsoMs", audit.TimingsBuildIsoMs);
    }

    private static void SetIfPresent(JsonObject doc, string key, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            doc[key] = value;
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
        List<string> requiredJobs = plan.Jobs.Jobs
            .Select(static j => j.Kind.ToWire())
            .Where(needed.Contains)
            .Distinct(StringComparer.Ordinal)
            .ToList();

        List<string> wingetIds = plan.WingetImportJson is { Length: > 0 }
            ? [.. ProductPosture.WingetIds]
            : [];

        ExpectedEvidenceFile expected = new(
            ExpectedEvidenceSchemaVersion,
            plan.Manifest.ImageQuality.ToString(),
            plan.PackageStrict,
            injectDrivers,
            expectFu,
            requiredKeys.Distinct(StringComparer.Ordinal).ToArray(),
            requiredValues,
            requiredJobs.ToArray(),
            wingetIds);
        File.WriteAllBytes(
            workspace.ExpectedEvidence,
            JsonSerializer.SerializeToUtf8Bytes(expected, ServicingJsonContext.Default.ExpectedEvidenceFile));
    }

    private static Result<MediaCacheIdentity, Failure> ResolveMediaIdentity(ServicingRun run, int wimIndex)
    {
        if (!string.IsNullOrWhiteSpace(run.SourceIsoSha256))
        {
            long length = new FileInfo(run.SourceIsoPath).Length;
            return MediaCacheIdentity.TryCreate(
                run.SourceIsoSha256,
                length,
                wimIndex,
                MediaCacheIdentity.CurrentSchema,
                out MediaCacheIdentity frozen,
                out Failure frozenError)
                ? Result.Ok<MediaCacheIdentity, Failure>(frozen)
                : Result.Fail<MediaCacheIdentity, Failure>(frozenError);
        }

        return MediaCacheIdentity.TryFromFile(run.SourceIsoPath, wimIndex, out MediaCacheIdentity computed, out Failure computedError)
            ? Result.Ok<MediaCacheIdentity, Failure>(computed)
            : Result.Fail<MediaCacheIdentity, Failure>(computedError);
    }

    private static Result<IReadOnlyList<ServicingStage>, Failure> Materialize(
        BuildArtifacts plan,
        ServicingRun run,
        ServicingWorkspace workspace)
    {
        string payloadDir = workspace.Payload;
        if (Directory.Exists(payloadDir))
        {
            Directory.Delete(payloadDir, recursive: true);
        }

        Directory.CreateDirectory(payloadDir);
        string mediaDir = workspace.Media;
        string mountDir = HostMountDir;
        string unattendPath = workspace.Unattend;
        string wimOut = workspace.InstallWim;
        string outputIso = run.OutputIsoPath;
        int wimIndex = run.WimIndex ?? DefaultProWimIndex;
        Result<MediaCacheIdentity, Failure> identity;
        Stopwatch identityClock = Stopwatch.StartNew();
        try
        {
            identity = ResolveMediaIdentity(run, wimIndex);
        }
        finally
        {
            identityClock.Stop();
        }

        if (!identity.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(identity.Error);
        }

        File.WriteAllText(unattendPath, plan.Unattend.Xml);

        File.WriteAllText(
            Path.Combine(payloadDir, "jobs.json"),
            JobsWire.Write(plan.Jobs.Jobs));

        if (plan.WingetImportJson is { Length: > 0 })
        {
            File.WriteAllBytes(Path.Combine(payloadDir, "winget-import.json"), plan.WingetImportJson);
        }

        string[] removeProvisionedAppx = plan.RemoveProvisionedAppx.ToArray();

        BundleFile bundle = new(
            BundleSchemaVersion,
            ShellStampGuestPath,
            plan.Account.Username,
            plan.Account.Password ?? "",
            plan.Dma.Enabled,
            plan.Dma.Settle is null
                ? null
                : new SettleFile(
                    plan.Dma.Settle.Locale!,
                    plan.Dma.Settle.GeoId!.Value,
                    plan.Dma.Settle.TimeZoneId!,
                    plan.Dma.Settle.LocationServicesEnabled!.Value),
            removeProvisionedAppx,
            plan.Manifest.RequiresNetwork,
            plan.PackageStrict);
        File.WriteAllText(
            Path.Combine(payloadDir, "bundle.json"),
            GuestBundleWire.Write(bundle));

        Result<string, Failure> setupComplete = StageSetupCompleteScript(payloadDir);
        if (!setupComplete.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(setupComplete.Error);
        }

        Result<string, Failure> supervisor = StageSupervisorBinary(payloadDir);
        if (!supervisor.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(supervisor.Error);
        }

        Result<string, Failure> shellSkel = StageShellSkel(payloadDir);
        if (!shellSkel.IsOk)
        {
            return Result.Fail<IReadOnlyList<ServicingStage>, Failure>(shellSkel.Error);
        }

        File.WriteAllBytes(
            Path.Combine(payloadDir, ServicingWorkspace.PoliciesFileName),
            JsonSerializer.SerializeToUtf8Bytes(
                plan.OfflinePolicies.ToArray(),
                ServicingJsonContext.Default.OfflinePolicyRowArray));

        if (plan.RemoveProvisionedAppx.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.PackageFamilyNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    plan.RemoveProvisionedAppx.ToArray(),
                    ServicingJsonContext.Default.StringArray));
        }

        if (plan.RemoveCapabilities.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.CapabilityNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    plan.RemoveCapabilities.ToArray(),
                    ServicingJsonContext.Default.StringArray));
        }

        if (plan.DisableOptionalFeatures.Count > 0)
        {
            File.WriteAllBytes(
                Path.Combine(payloadDir, ServicingWorkspace.FeatureNamesFileName),
                JsonSerializer.SerializeToUtf8Bytes(
                    plan.DisableOptionalFeatures.ToArray(),
                    ServicingJsonContext.Default.StringArray));
        }

        List<ServicingStage> resolved = new(plan.Stages.Stages.Count);
        List<(ServicingOpcode Opcode, JsonObject Parameters)> wire = new(plan.Stages.Stages.Count);
        void Add<T>(ServicingOpcode opcode, T record, JsonTypeInfo<T> typeInfo)
        {
            JsonObject obj = StageParamJson.From(record, typeInfo);
            wire.Add((opcode, obj));
            resolved.Add(new ServicingStage(opcode, StageParamJson.ToBag(obj)));
        }

        foreach (ServicingStage stage in plan.Stages.Stages)
        {
            switch (stage.Opcode)
            {
                case ServicingOpcode.MountInstallWim:
                    Add(
                        stage.Opcode,
                        new MountInstallWimParameters(
                            SourceIso: run.SourceIsoPath,
                            MountDir: mountDir,
                            MediaDir: mediaDir,
                            WimIndex: wimIndex,
                            WorkDirectory: workspace.Root,
                            SourceIsoSha256: identity.Value.SourceIsoSha256,
                            SourceIsoLength: identity.Value.SourceIsoLength,
                            CacheSchema: identity.Value.Schema,
                            CacheRoot: MediaCacheIdentity.Root,
                            ImageName: run.SelectedImage?.Name,
                            Architecture: run.SelectedImage?.Architecture,
                            ImageEdition: run.SelectedImage?.Edition,
                            ImageBuild: run.SelectedImage?.Build),
                        ServicingJsonContext.Default.MountInstallWimParameters);
                    break;
                case ServicingOpcode.StagePayload:
                    Add(
                        stage.Opcode,
                        new StagePayloadParameters(payloadDir, mountDir),
                        ServicingJsonContext.Default.StagePayloadParameters);
                    break;
                case ServicingOpcode.StageOobeUnattend:
                    Add(
                        stage.Opcode,
                        new StageOobeUnattendParameters(unattendPath, mountDir, mediaDir),
                        ServicingJsonContext.Default.StageOobeUnattendParameters);
                    break;
                case ServicingOpcode.PatchBootWimApply:
                    Add(
                        stage.Opcode,
                        new PatchBootWimApplyParameters(mediaDir, mountDir, workspace.Root),
                        ServicingJsonContext.Default.PatchBootWimApplyParameters);
                    break;
                case ServicingOpcode.StampOfflineShell:
                    Add(
                        stage.Opcode,
                        new StampOfflineShellParameters(ShellStampGuestPath, mountDir),
                        ServicingJsonContext.Default.StampOfflineShellParameters);
                    break;
                case ServicingOpcode.StampOfflinePolicies:
                    Add(
                        stage.Opcode,
                        new StampOfflinePoliciesParameters(
                            mountDir,
                            run.WorkDirectory,
                            Path.Combine(payloadDir, ServicingWorkspace.PoliciesFileName)),
                        ServicingJsonContext.Default.StampOfflinePoliciesParameters);
                    break;
                case ServicingOpcode.RemoveProvisionedAppx:
                    Add(
                        stage.Opcode,
                        new RemoveProvisionedAppxParameters(
                            mountDir,
                            run.WorkDirectory,
                            Path.Combine(payloadDir, ServicingWorkspace.PackageFamilyNamesFileName)),
                        ServicingJsonContext.Default.RemoveProvisionedAppxParameters);
                    break;
                case ServicingOpcode.RemoveCapabilities:
                    Add(
                        stage.Opcode,
                        new RemoveCapabilitiesParameters(
                            mountDir,
                            run.WorkDirectory,
                            "capability",
                            Path.Combine(payloadDir, ServicingWorkspace.CapabilityNamesFileName)),
                        ServicingJsonContext.Default.RemoveCapabilitiesParameters);
                    break;
                case ServicingOpcode.DisableOptionalFeatures:
                    Add(
                        stage.Opcode,
                        new DisableOptionalFeaturesParameters(
                            mountDir,
                            run.WorkDirectory,
                            "feature",
                            Path.Combine(payloadDir, ServicingWorkspace.FeatureNamesFileName)),
                        ServicingJsonContext.Default.DisableOptionalFeaturesParameters);
                    break;
                case ServicingOpcode.InjectDrivers:
                    Add(
                        stage.Opcode,
                        new InjectDriversParameters(
                            mountDir,
                            run.WorkDirectory,
                            mediaDir,
                            stage.Parameters[StageParams.DeviceId],
                            stage.Parameters[StageParams.DetailsUrl],
                            stage.Parameters[StageParams.ExpectedFileNameRegex]),
                        ServicingJsonContext.Default.InjectDriversParameters);
                    break;
                case ServicingOpcode.ExportWim:
                    Add(
                        stage.Opcode,
                        new ExportWimParameters(
                            mountDir,
                            mediaDir,
                            wimOut,
                            run.WorkDirectory,
                            stage.Parameters[StageParams.Lane],
                            stage.Parameters[StageParams.Compression],
                            stage.Parameters[StageParams.Cleanup]),
                        ServicingJsonContext.Default.ExportWimParameters);
                    break;
                case ServicingOpcode.BuildIso:
                    Add(
                        stage.Opcode,
                        new BuildIsoParameters(outputIso, mediaDir),
                        ServicingJsonContext.Default.BuildIsoParameters);
                    break;
                default:
                    throw new InvalidOperationException($"Unhandled opcode {stage.Opcode}");
            }
        }

        File.WriteAllText(workspace.Stages, SerializeServicingStagesFile(wire));
        workspace.WriteManifest();
        WriteExpectedEvidence(workspace, plan, resolved);

        return Result.Ok<IReadOnlyList<ServicingStage>, Failure>(resolved.ToArray());
    }

    private static Result<string, Failure> StageSetupCompleteScript(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "SetupComplete.cmd");
        string? source = FindSetupCompleteScript();
        if (source is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.setupComplete.missing",
                    "payload/scripts/SetupComplete.cmd not found."));
        }

        File.Copy(source, dest, overwrite: true);
        return Result.Ok<string, Failure>(dest);
    }

    private static Result<string, Failure> StageSupervisorBinary(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "Supervisor.exe");
        string? published = FindPublishedSupervisor();
        if (published is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.supervisor.missing",
                    "Published Supervisor not found. Run: just publish-provisioning"));
        }

        File.Copy(published, dest, overwrite: true);
        return Result.Ok<string, Failure>(dest);
    }

    private static Result<string, Failure> StageShellSkel(string payloadDir)
    {
        string? source = FindShellSkelDirectory();
        if (source is null)
        {
            return Result.Fail<string, Failure>(
                new Failure(
                    "servicing.shellSkel.missing",
                    "payload/shell-skel not found."));
        }

        string dest = Path.Combine(payloadDir, "shell-skel");
        CopyDirectory(source, dest);
        return Result.Ok<string, Failure>(dest);
    }

    private static void CopyDirectory(string sourceDir, string destDir)
    {
        Directory.CreateDirectory(destDir);
        foreach (string file in Directory.EnumerateFiles(sourceDir))
        {
            File.Copy(file, Path.Combine(destDir, Path.GetFileName(file)), overwrite: true);
        }

        foreach (string dir in Directory.EnumerateDirectories(sourceDir))
        {
            CopyDirectory(dir, Path.Combine(destDir, Path.GetFileName(dir)));
        }
    }

    private static string? FindShellSkelDirectory() =>
        ToolkitRoot.TryFind("payload", "shell-skel");

    private static string? FindSetupCompleteScript() =>
        ToolkitRoot.TryFind("payload", "scripts", "SetupComplete.cmd");

    private static string? FindPublishedSupervisor()
    {
        string sideBySide = Path.Combine(AppContext.BaseDirectory, "WinMint.Provisioning.exe");
        return ToolkitRoot.TryFind("artifacts", "provisioning", "WinMint.Provisioning.exe")
            ?? (File.Exists(sideBySide) ? sideBySide : null);
    }

    /// <summary>Guest code compiled into the Supervisor — Provisioning plus the contracts it links.</summary>
    private static readonly string[] SupervisorSourceProjects =
        ["WinMint.Provisioning", "WinMint.Contracts"];

    /// <summary>
    /// Refuses a compile whose published Supervisor predates guest source. Staging copies whatever it
    /// finds, so a forgotten republish once shipped an ISO whose guest behaviour silently predated the
    /// tree that built it — the machine then fails in ways the source no longer explains.
    /// </summary>
    /// <returns>Null when the publish is current, absent, or unverifiable.</returns>
    public static Failure? CheckSupervisorFreshness()
    {
        string? published = FindPublishedSupervisor();
        if (published is null)
        {
            return null; // Staging reports the missing publish with its own remedy.
        }

        string? staleSince = SupervisorSourceProjects
            .Select(static project => ToolkitRoot.TryFind("src", project))
            .Select(root => FindSourceNewerThan(published, root))
            .FirstOrDefault(static hit => hit is not null);

        return staleSince is null
            ? null
            : new Failure(
                "hostCompile.supervisor.stale",
                $"Published Supervisor predates '{staleSince}'. An ISO built now would ship guest code "
                + "that no longer matches this tree. Run: just publish-provisioning");
    }

    /// <summary>
    /// First <c>*.cs</c> under <paramref name="sourceRoot"/> newer than the published binary.
    /// Null when source is absent — a packaged toolkit ships without <c>src/</c> and cannot check.
    /// </summary>
    internal static string? FindSourceNewerThan(string publishedExe, string? sourceRoot)
    {
        if (sourceRoot is null || !Directory.Exists(sourceRoot))
        {
            return null;
        }

        // ponytail: mtime, not content hash — a clock skew or a no-op touch gives a false "stale".
        // That errs toward an extra publish; upgrade to hashing inputs only if that becomes noise.
        DateTime published = File.GetLastWriteTimeUtc(publishedExe);
        return Directory
            .EnumerateFiles(sourceRoot, "*.cs", SearchOption.AllDirectories)
            .Where(static file =>
                !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
            .FirstOrDefault(file => File.GetLastWriteTimeUtc(file) > published);
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
