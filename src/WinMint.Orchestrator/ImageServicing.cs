using System.Collections.Frozen;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public const string EvidenceSchemaVersion = "winmint.image.evidence/v1";
    public const string ExpectedEvidenceSchemaVersion = "winmint.expected-evidence/v1";
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

        if (IsStoreMsixPwsh(CurrentProcessPath()))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.pwsh.storeMsix",
                    "Host PowerShell is Microsoft Store MSIX; DISM/AppX offline servicing requires WinPS 5.1 or non-Store pwsh (install from GitHub)."));
        }

        if (string.IsNullOrWhiteSpace(run.SourceIsoPath) || !File.Exists(run.SourceIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.sourceIso.missing", $"Source ISO not found: {run.SourceIsoPath}"));
        }

        ServicingRun normalized = NormalizeOutputIso(run, plan.Manifest.ImageQuality);

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

    /// <summary>Resolve default Output ISO once; Materialize/evidence never invent a leaf.</summary>
    private static ServicingRun NormalizeOutputIso(ServicingRun run, ImageQualityLane lane)
    {
        if (!string.IsNullOrWhiteSpace(run.OutputIsoPath))
        {
            return run with { OutputIsoPath = run.OutputIsoPath.Trim() };
        }

        return run with
        {
            OutputIsoPath = OutputIsoNaming.DefaultPath(run.WorkDirectory, run.ProfilePath, lane),
        };
    }

    private static Result<ImageEvidence, Failure> WriteEvidence(
        ServicingWorkspace workspace,
        BuildArtifacts plan,
        ServicingRun run,
        IReadOnlyList<ServicingStage> stages)
    {
        if (string.IsNullOrWhiteSpace(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.outputIso.missing",
                    "OutputIsoPath was not normalized before evidence write."));
        }

        if (!File.Exists(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.outputIso.missing", "BuildIso output missing."));
        }

        ServicingStage? stamp = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.StampOfflineShell);
        if (stamp is null
            || !stamp.Parameters.TryGetValue(StageParams.ShellTarget, out string? shellTarget)
            || string.IsNullOrWhiteSpace(shellTarget))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.shellStamp.missing",
                    "StampOfflineShell stage missing or incomplete."));
        }

        ServicingStage? export = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.ExportWim);
        if (export is null
            || !export.Parameters.TryGetValue(StageParams.Lane, out string? lane)
            || string.IsNullOrWhiteSpace(lane))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.lane.missing", "ExportWim stage missing lane."));
        }

        string plannedLane = plan.Manifest.ImageQuality.ToString();
        if (!string.Equals(lane, plannedLane, StringComparison.Ordinal))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.lane.mismatch",
                    $"ExportWim lane '{lane}' does not match planned lane '{plannedLane}'."));
        }

        Dictionary<string, string> digests = new(StringComparer.Ordinal);
        if (File.Exists(workspace.Digests))
        {
            try
            {
                JsonNode? side = JsonNode.Parse(File.ReadAllBytes(workspace.Digests));
                if (side is JsonObject obj)
                {
                    foreach (KeyValuePair<string, JsonNode?> p in obj)
                    {
                        if (p.Value is not null)
                        {
                            digests[p.Key] = p.Value.ToString();
                        }
                    }
                }
            }
            catch (JsonException ex)
            {
                return Result.Fail<ImageEvidence, Failure>(
                    new Failure("servicing.evidence.invalid", ex.Message));
            }
        }

        if (File.Exists(workspace.InstallWim))
        {
            digests["installWim.sha256"] = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(workspace.InstallWim)));
        }

        string outputIsoSha256 = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(run.OutputIsoPath)));
        digests["outputIso.sha256"] = outputIsoSha256;

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
            try
            {
                JsonNode? sidecar = JsonNode.Parse(File.ReadAllBytes(workspace.PreparedMedia));
                if (sidecar is JsonObject extra)
                {
                    foreach (KeyValuePair<string, JsonNode?> p in extra)
                    {
                        if (p.Key == "mediaCache.previousMedia")
                        {
                            continue;
                        }

                        doc[p.Key] = p.Value?.DeepClone();
                    }
                }
            }
            catch (JsonException)
            {
                // ponytail: sidecar is audit-only; a corrupt file must not block Output ISO evidence
            }
        }

        File.WriteAllText(workspace.Evidence, doc.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

        return Result.Ok<ImageEvidence, Failure>(
            new ImageEvidence(
                run.OutputIsoPath,
                plan.Manifest.ImageQuality,
                shellTarget,
                digests.ToFrozenDictionary(StringComparer.Ordinal)));
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
        // NormalizeOutputIso already set OutputIsoPath before Materialize.
        string outputIso = run.OutputIsoPath
            ?? throw new InvalidOperationException("OutputIsoPath must be normalized before Materialize.");
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
        File.WriteAllBytes(
            Path.Combine(payloadDir, "bundle.json"),
            JsonSerializer.SerializeToUtf8Bytes(bundle, ServicingJsonContext.Default.BundleFile));

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
        foreach (ServicingStage stage in plan.Stages.Stages)
        {
            Dictionary<string, string> parameters = stage.Opcode switch
            {
                ServicingOpcode.MountInstallWim => StageParamBag.From(
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
                    ServicingJsonContext.Default.MountInstallWimParameters),
                ServicingOpcode.StagePayload => StageParamBag.From(
                    new StagePayloadParameters(payloadDir, mountDir),
                    ServicingJsonContext.Default.StagePayloadParameters),
                ServicingOpcode.StageOobeUnattend => StageParamBag.From(
                    new StageOobeUnattendParameters(unattendPath, mountDir, mediaDir),
                    ServicingJsonContext.Default.StageOobeUnattendParameters),
                ServicingOpcode.PatchBootWimApply => StageParamBag.From(
                    new PatchBootWimApplyParameters(mediaDir, mountDir, workspace.Root),
                    ServicingJsonContext.Default.PatchBootWimApplyParameters),
                ServicingOpcode.StampOfflineShell => StageParamBag.From(
                    new StampOfflineShellParameters(ShellStampGuestPath, mountDir),
                    ServicingJsonContext.Default.StampOfflineShellParameters),
                ServicingOpcode.StampOfflinePolicies => StageParamBag.From(
                    new StampOfflinePoliciesParameters(
                        mountDir,
                        run.WorkDirectory,
                        Path.Combine(payloadDir, ServicingWorkspace.PoliciesFileName)),
                    ServicingJsonContext.Default.StampOfflinePoliciesParameters),
                ServicingOpcode.RemoveProvisionedAppx => StageParamBag.From(
                    new RemoveProvisionedAppxParameters(
                        mountDir,
                        run.WorkDirectory,
                        Path.Combine(payloadDir, ServicingWorkspace.PackageFamilyNamesFileName)),
                    ServicingJsonContext.Default.RemoveProvisionedAppxParameters),
                ServicingOpcode.RemoveCapabilities => StageParamBag.From(
                    new OfflineComponentParameters(
                        mountDir,
                        run.WorkDirectory,
                        "capability",
                        Path.Combine(payloadDir, ServicingWorkspace.CapabilityNamesFileName)),
                    ServicingJsonContext.Default.OfflineComponentParameters),
                ServicingOpcode.DisableOptionalFeatures => StageParamBag.From(
                    new OfflineComponentParameters(
                        mountDir,
                        run.WorkDirectory,
                        "feature",
                        Path.Combine(payloadDir, ServicingWorkspace.FeatureNamesFileName)),
                    ServicingJsonContext.Default.OfflineComponentParameters),
                ServicingOpcode.InjectDrivers => StageParamBag.From(
                    new InjectDriversParameters(
                        mountDir,
                        run.WorkDirectory,
                        mediaDir,
                        stage.Parameters[StageParams.DeviceId],
                        stage.Parameters[StageParams.DetailsUrl],
                        stage.Parameters[StageParams.ExpectedFileNameRegex]),
                    ServicingJsonContext.Default.InjectDriversParameters),
                ServicingOpcode.ExportWim => StageParamBag.From(
                    new ExportWimParameters(
                        mountDir,
                        mediaDir,
                        wimOut,
                        run.WorkDirectory,
                        stage.Parameters[StageParams.Lane],
                        stage.Parameters[StageParams.Compression],
                        stage.Parameters[StageParams.Cleanup]),
                    ServicingJsonContext.Default.ExportWimParameters),
                ServicingOpcode.BuildIso => StageParamBag.From(
                    new BuildIsoParameters(outputIso, mediaDir),
                    ServicingJsonContext.Default.BuildIsoParameters),
                _ => throw new InvalidOperationException($"Unhandled opcode {stage.Opcode}"),
            };

            resolved.Add(new ServicingStage(stage.Opcode, parameters));
        }

        File.WriteAllText(
            workspace.Stages,
            BuildPlan.SerializeServicingStagesFile(new ServicingStageList(resolved)));
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

    /// <summary>Store MSIX pwsh breaks DISM/AppX offline servicing; fail closed on Apply.</summary>
    internal static bool IsStoreMsixPwsh(string? processPath)
    {
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return false;
        }

        string path = processPath.Replace('/', '\\');
        return path.Contains(@"\WindowsApps\Microsoft.PowerShell", StringComparison.OrdinalIgnoreCase)
            || path.Contains(@"\WindowsApps\Microsoft.PowerShellPreview", StringComparison.OrdinalIgnoreCase);
    }

    private static string? CurrentProcessPath()
    {
        try
        {
            return Environment.ProcessPath;
        }
        catch
        {
            return null;
        }
    }
}

internal sealed record FailureFile(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("message")] string? Message,
    [property: JsonPropertyName("opcode")] string? Opcode);

[JsonSerializable(typeof(BundleFile))]
[JsonSerializable(typeof(ExpectedEvidenceFile))]
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
[JsonSerializable(typeof(OfflineComponentParameters))]
[JsonSerializable(typeof(InjectDriversParameters))]
[JsonSerializable(typeof(ExportWimParameters))]
[JsonSerializable(typeof(BuildIsoParameters))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ServicingJsonContext : JsonSerializerContext;
