using System.Collections.Frozen;
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
        Directory.CreateDirectory(Path.Combine(normalized.WorkDirectory, "payload"));
        Directory.CreateDirectory(HostServicingRoot);

        Result<IReadOnlyList<ServicingStage>, Failure> materialized = Materialize(plan, normalized);
        if (!materialized.IsOk)
        {
            return Result.Fail<ImageEvidence, Failure>(materialized.Error);
        }

        if (ValidateExportLaneParams(plan, materialized.Value) is { } laneError)
        {
            return Result.Fail<ImageEvidence, Failure>(laneError);
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
        catch (JsonException ex)
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

        if (string.IsNullOrWhiteSpace(run.OutputIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "servicing.outputIso.missing",
                    "OutputIsoPath was not normalized before evidence read."));
        }

        return Result.Ok<ImageEvidence, Failure>(
            new ImageEvidence(
                file.OutputIsoPath ?? run.OutputIsoPath,
                plan.Manifest.ImageQuality,
                file.ShellStampTargetPath ?? shellTarget,
                file.Digests?.ToFrozenDictionary(StringComparer.Ordinal)
                    ?? (IReadOnlyDictionary<string, string>)FrozenDictionary<string, string>.Empty));
    }

    /// <summary>
    /// Ticket 09: ExportWim compression/cleanup must match manifest lane (Test vs Release).
    /// </summary>
    private static Failure? ValidateExportLaneParams(
        BuildArtifacts plan,
        IReadOnlyList<ServicingStage> stages)
    {
        ServicingStage? export = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.ExportWim);
        if (export is null)
        {
            return new Failure("servicing.export.missing", "Plan is missing ExportWim stage.");
        }

        string expectedLane;
        string expectedCompression;
        string expectedCleanup;
        if (plan.Manifest.ImageQuality == ImageQualityLane.Release)
        {
            expectedLane = "Release";
            expectedCompression = "max";
            expectedCleanup = "full";
        }
        else
        {
            expectedLane = "Test";
            expectedCompression = "fast";
            expectedCleanup = "skip";
        }

        if (!export.Parameters.TryGetValue(StageParams.Lane, out string? lane)
            || !export.Parameters.TryGetValue(StageParams.Compression, out string? compression)
            || !export.Parameters.TryGetValue(StageParams.Cleanup, out string? cleanup)
            || !string.Equals(lane, expectedLane, StringComparison.Ordinal)
            || !string.Equals(compression, expectedCompression, StringComparison.Ordinal)
            || !string.Equals(cleanup, expectedCleanup, StringComparison.Ordinal))
        {
            return new Failure(
                "servicing.export.laneMismatch",
                $"ExportWim params must be lane={expectedLane} compression={expectedCompression} cleanup={expectedCleanup} for ImageQuality={plan.Manifest.ImageQuality}.");
        }

        return null;
    }

    private static Result<IReadOnlyList<ServicingStage>, Failure> Materialize(BuildArtifacts plan, ServicingRun run)
    {
        string payloadDir = Path.Combine(run.WorkDirectory, "payload");
        string mediaDir = Path.Combine(run.WorkDirectory, "media");
        string mountDir = HostMountDir;
        string unattendPath = Path.Combine(run.WorkDirectory, "unattend.xml");
        string wimOut = Path.Combine(run.WorkDirectory, "install.wim");
        // NormalizeOutputIso already set OutputIsoPath before Materialize.
        string outputIso = run.OutputIsoPath
            ?? throw new InvalidOperationException("OutputIsoPath must be normalized before Materialize.");
        int wimIndex = run.WimIndex ?? DefaultProWimIndex;

        File.WriteAllText(unattendPath, plan.Unattend.Xml);

        File.WriteAllText(
            Path.Combine(payloadDir, "jobs.json"),
            BuildPlan.SerializeJobsFile(plan.Jobs));

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
                    parameters[StageParams.ReuseMedia] = run.ReuseMedia ? "true" : "false";
                    parameters[StageParams.WorkDirectory] = run.WorkDirectory;
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
            BuildPlan.SerializeStagesFile(new ServicingStageList(resolved)));

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
