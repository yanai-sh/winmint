using System.Collections.Frozen;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public const string EvidenceSchemaVersion = "winmint.image.evidence/v1";
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

        Directory.CreateDirectory(normalized.WorkDirectory);
        Directory.CreateDirectory(Path.Combine(normalized.WorkDirectory, "logs"));
        Directory.CreateDirectory(HostServicingRoot);

        Result<IReadOnlyList<ServicingStage>, Failure> materialized = Materialize(plan, normalized);
        if (!materialized.IsOk)
        {
            return Result.Fail<ImageEvidence, Failure>(materialized.Error);
        }

        // Materialize already wrote stages.json; that file is the seam (Invoke-ServicingPlan.ps1 reads it).
        Result<ElevatedRunOk, Failure> elevated = await runner.ExecuteAsync(normalized.WorkDirectory, ct)
            .ConfigureAwait(false);
        if (!elevated.IsOk)
        {
            // Invariant: never delete workdir on failure (or success) — caller owns lifetime.
            return Result.Fail<ImageEvidence, Failure>(elevated.Error);
        }

        return ReadEvidence(normalized.WorkDirectory, plan, normalized, materialized.Value);
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

    private static Result<ImageEvidence, Failure> ReadEvidence(
        string workDirectory,
        BuildArtifacts plan,
        ServicingRun run,
        IReadOnlyList<ServicingStage> stages)
    {
        string evidencePath = Path.Combine(workDirectory, "evidence.json");
        if (!File.Exists(evidencePath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.missing", "Invoke-ServicingPlan succeeded but evidence.json is missing."));
        }

        EvidenceFile? file;
        try
        {
            file = JsonSerializer.Deserialize(
                File.ReadAllBytes(evidencePath),
                ServicingJsonContext.Default.EvidenceFile);
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.invalid", ex.Message));
        }

        if (file is null
            || !string.Equals(file.SchemaVersion, EvidenceSchemaVersion, StringComparison.Ordinal))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.schema",
                    $"Expected {EvidenceSchemaVersion}."));
        }

        if (string.IsNullOrWhiteSpace(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.outputIso.missing",
                    "OutputIsoPath was not normalized before evidence read."));
        }

        if (string.IsNullOrWhiteSpace(file.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.outputIso.missing", "Evidence outputIsoPath is required."));
        }

        if (!WindowsPathsEqual(file.OutputIsoPath, run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.outputIso.mismatch",
                    $"Evidence outputIsoPath does not match planned output: {file.OutputIsoPath}"));
        }

        string plannedLane = plan.Manifest.ImageQuality.ToString();
        if (string.IsNullOrWhiteSpace(file.Lane))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.lane.missing", "Evidence lane is required."));
        }

        if (!string.Equals(file.Lane, plannedLane, StringComparison.Ordinal))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.lane.mismatch",
                    $"Evidence lane '{file.Lane}' does not match planned lane '{plannedLane}'."));
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

        if (string.IsNullOrWhiteSpace(file.ShellStampTargetPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.shellStamp.missing",
                    "Evidence shellStampTargetPath is required."));
        }

        if (!string.Equals(file.ShellStampTargetPath, shellTarget, StringComparison.OrdinalIgnoreCase))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.shellStamp.mismatch",
                    $"Evidence shell target '{file.ShellStampTargetPath}' does not match planned target '{shellTarget}'."));
        }

        if (file.Digests is null)
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("servicing.evidence.digests.missing", "Evidence digests are required."));
        }

        if (!file.Digests.TryGetValue("outputIso.sha256", out string? outputIsoSha256)
            || !IsLowerSha256(outputIsoSha256))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.evidence.outputIsoDigest.invalid",
                    "Evidence outputIso.sha256 must be a lowercase 64-character hexadecimal digest."));
        }

        return Result.Ok<ImageEvidence, Failure>(
            new ImageEvidence(
                run.OutputIsoPath,
                plan.Manifest.ImageQuality,
                shellTarget,
                file.Digests.ToFrozenDictionary(StringComparer.Ordinal)));
    }

    private static bool WindowsPathsEqual(string left, string right)
    {
        try
        {
            string normalizedLeft = Path.TrimEndingDirectorySeparator(Path.GetFullPath(left.Trim()));
            string normalizedRight = Path.TrimEndingDirectorySeparator(Path.GetFullPath(right.Trim()));
            return string.Equals(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    private static bool IsLowerSha256(string? value) =>
        value is { Length: 64 }
        && value.All(static c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

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

    private static Result<IReadOnlyList<ServicingStage>, Failure> Materialize(BuildArtifacts plan, ServicingRun run)
    {
        string payloadDir = Path.Combine(run.WorkDirectory, "payload");
        if (Directory.Exists(payloadDir))
        {
            Directory.Delete(payloadDir, recursive: true);
        }

        Directory.CreateDirectory(payloadDir);
        string mediaDir = Path.Combine(run.WorkDirectory, "media");
        string mountDir = HostMountDir;
        string unattendPath = Path.Combine(run.WorkDirectory, "unattend.xml");
        string wimOut = Path.Combine(run.WorkDirectory, "install.wim");
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

        List<ServicingStage> resolved = new(plan.Stages.Stages.Count);
        foreach (ServicingStage stage in plan.Stages.Stages)
        {
            Dictionary<string, string> parameters = new(stage.Parameters, StringComparer.Ordinal);
            switch (stage.Opcode)
            {
                case ServicingOpcode.MountInstallWim:
                    parameters[StageParams.SourceIso] = run.SourceIsoPath;
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.MediaDir] = mediaDir;
                    parameters[StageParams.WimIndex] = wimIndex.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    parameters[StageParams.SourceIsoSha256] = identity.Value.SourceIsoSha256;
                    parameters[StageParams.SourceIsoLength] = identity.Value.SourceIsoLength.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    parameters[StageParams.CacheSchema] = identity.Value.Schema.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    parameters[StageParams.CacheRoot] = MediaCacheIdentity.Root;
                    if (run.SelectedImage is { } selected)
                    {
                        parameters[StageParams.ImageName] = selected.Name;
                        parameters[StageParams.Architecture] = selected.Architecture ?? "";
                        parameters[StageParams.ImageEdition] = selected.Edition ?? "";
                        parameters[StageParams.ImageBuild] = selected.Build ?? "";
                    }
                    break;
                case ServicingOpcode.StagePayload:
                    parameters[StageParams.PayloadDir] = payloadDir;
                    parameters[StageParams.MountDir] = mountDir;
                    break;
                case ServicingOpcode.StageOobeUnattend:
                    parameters[StageParams.UnattendPath] = unattendPath;
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.MediaDir] = mediaDir;
                    break;
                case ServicingOpcode.PatchBootWimApply:
                    // Single-image install.wim apply target is always index 1 (Patch-BootWimApply.ps1).
                    // Do not pass source-edition wimIndex — that previously poisoned LaunchApply.cmd.
                    parameters[StageParams.MediaDir] = mediaDir;
                    parameters[StageParams.MountDir] = mountDir;
                    break;
                case ServicingOpcode.StampOfflineShell:
                    parameters[StageParams.ShellTarget] = ShellStampGuestPath;
                    parameters[StageParams.MountDir] = mountDir;
                    break;
                case ServicingOpcode.StampOfflinePolicies:
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    break;
                case ServicingOpcode.RemoveProvisionedAppx:
                    // packageFamilyNames comes from BuildPlan — inject mount + workdir for logs.
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    break;
                case ServicingOpcode.RemoveCapabilities:
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    parameters[StageParams.Kind] = "capability";
                    break;
                case ServicingOpcode.DisableOptionalFeatures:
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    parameters[StageParams.Kind] = "feature";
                    break;
                case ServicingOpcode.InjectDrivers:
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    parameters[StageParams.MediaDir] = mediaDir;
                    break;
                case ServicingOpcode.ExportWim:
                    // compression / cleanup / lane come from BuildPlan — do not invent defaults here.
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.MediaDir] = mediaDir;
                    parameters[StageParams.WimOut] = wimOut;
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
                    break;
                case ServicingOpcode.BuildIso:
                    parameters[StageParams.OutputIso] = outputIso;
                    parameters[StageParams.MediaDir] = mediaDir;
                    break;
            }

            resolved.Add(new ServicingStage(stage.Opcode, parameters));
        }

        File.WriteAllText(
            Path.Combine(run.WorkDirectory, "stages.json"),
            BuildPlan.SerializeServicingStagesFile(new ServicingStageList(resolved)));

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

internal sealed record EvidenceFile(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("outputIsoPath")] string? OutputIsoPath,
    [property: JsonPropertyName("shellStampTargetPath")] string? ShellStampTargetPath,
    [property: JsonPropertyName("lane")] string? Lane,
    [property: JsonPropertyName("packageStrict")] bool PackageStrict,
    [property: JsonPropertyName("digests")] Dictionary<string, string>? Digests);

internal sealed record FailureFile(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("message")] string? Message,
    [property: JsonPropertyName("opcode")] string? Opcode);

[JsonSerializable(typeof(BundleFile))]
[JsonSerializable(typeof(EvidenceFile))]
[JsonSerializable(typeof(FailureFile))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ServicingJsonContext : JsonSerializerContext;
