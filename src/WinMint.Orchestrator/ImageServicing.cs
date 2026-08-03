using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public const string EvidenceSchemaVersion = "winmint.image.evidence/v1";
    public const string BundleSchemaVersion = "winmint.provisioning.bundle/v1";

    /// <summary>Guest path stamped into Winlogon Shell (offline); Machine setup verifies the same path.</summary>
    public const string ShellStampGuestPath = @"C:\Windows\WinMint\Supervisor.exe";

    /// <summary>Smoke default: Windows 11 Pro on consumer multi-edition ARM64/x64 ISOs (Home=1, Home SL=2, Pro=3).
    /// MountInstallWim exports this index to a single-image WIM before mount (IMAGESERVICING invariant 7).</summary>
    public const int DefaultProWimIndex = 3;

    public static Result<ImageEvidence, ServicingFailure> Apply(
        BuildArtifacts plan,
        ServicingRun run,
        CancellationToken ct = default) =>
        Apply(plan, run, new PwshElevatedPlanRunner(), ct);

    public static Result<ImageEvidence, ServicingFailure> Apply(
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
            return Result.Fail<ImageEvidence, ServicingFailure>(
                new ServicingFailure("servicing.workdir.missing", "WorkDirectory is required."));
        }

        if (string.IsNullOrWhiteSpace(run.SourceIsoPath) || !File.Exists(run.SourceIsoPath))
        {
            return Result.Fail<ImageEvidence, ServicingFailure>(
                new ServicingFailure("servicing.sourceIso.missing", $"Source ISO not found: {run.SourceIsoPath}"));
        }

        Directory.CreateDirectory(run.WorkDirectory);
        Directory.CreateDirectory(Path.Combine(run.WorkDirectory, "logs"));
        Directory.CreateDirectory(Path.Combine(run.WorkDirectory, "payload"));

        Result<List<ServicingStage>, ServicingFailure> materialized = Materialize(plan, run);
        if (!materialized.IsOk)
        {
            return Result.Fail<ImageEvidence, ServicingFailure>(materialized.Error);
        }

        Result<ImageEvidence, ServicingFailure> outcome = runner.Execute(
            run.WorkDirectory,
            materialized.Value,
            run,
            plan,
            ct);
        // Invariant: never delete workdir on failure (or success) — caller owns lifetime.
        return outcome;
    }

    private static Result<List<ServicingStage>, ServicingFailure> Materialize(BuildArtifacts plan, ServicingRun run)
    {
        string payloadDir = Path.Combine(run.WorkDirectory, "payload");
        string mediaDir = Path.Combine(run.WorkDirectory, "media");
        string mountDir = Path.Combine(run.WorkDirectory, "mount");
        string unattendPath = Path.Combine(run.WorkDirectory, "unattend.xml");
        string wimOut = Path.Combine(run.WorkDirectory, "install.wim");
        string outputIso = run.OutputIsoPath ?? Path.Combine(run.WorkDirectory, "out.iso");
        int wimIndex = run.WimIndex ?? DefaultProWimIndex;

        File.WriteAllText(unattendPath, plan.Unattend.Xml);

        JobsFile jobs = new(plan.Jobs.SchemaVersion, plan.Jobs.Jobs.Select(j => new JobFile(j.Id, j.Kind)).ToArray());
        File.WriteAllText(
            Path.Combine(run.WorkDirectory, "jobs.json"),
            JsonSerializer.Serialize(jobs, ServicingJsonContext.Default.JobsFile));
        File.WriteAllText(
            Path.Combine(payloadDir, "jobs.json"),
            JsonSerializer.Serialize(jobs, ServicingJsonContext.Default.JobsFile));

        BundleFile bundle = new(
            BundleSchemaVersion,
            ShellStampGuestPath,
            plan.Account.Username,
            plan.Account.Password ?? "",
            plan.Dma.Enabled,
            plan.Dma.Settle is null
                ? null
                : new SettleFile(
                    plan.Dma.Settle.Locale,
                    plan.Dma.Settle.GeoId,
                    plan.Dma.Settle.TimeZoneId,
                    plan.Dma.Settle.LocationServicesEnabled),
            plan.Jobs.Jobs.Select(j => j.Id).ToArray());
        File.WriteAllText(
            Path.Combine(payloadDir, "bundle.json"),
            JsonSerializer.Serialize(bundle, ServicingJsonContext.Default.BundleFile));

        Result<string, ServicingFailure> setupComplete = StageSetupCompleteScript(payloadDir);
        if (!setupComplete.IsOk)
        {
            return Result.Fail<List<ServicingStage>, ServicingFailure>(setupComplete.Error);
        }

        Result<string, ServicingFailure> supervisor = StageSupervisorBinary(payloadDir);
        if (!supervisor.IsOk)
        {
            return Result.Fail<List<ServicingStage>, ServicingFailure>(supervisor.Error);
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
                    break;
                case ServicingOpcode.StagePayload:
                    parameters[StageParams.PayloadDir] = payloadDir;
                    parameters[StageParams.MountDir] = mountDir;
                    break;
                case ServicingOpcode.InjectUnattend:
                    parameters[StageParams.UnattendPath] = unattendPath;
                    parameters[StageParams.MountDir] = mountDir;
                    break;
                case ServicingOpcode.StampOfflineShell:
                    parameters[StageParams.ShellTarget] = ShellStampGuestPath;
                    parameters[StageParams.MountDir] = mountDir;
                    break;
                case ServicingOpcode.ExportWim:
                    // compression / cleanup / lane come from BuildPlan — do not invent defaults here.
                    parameters[StageParams.MountDir] = mountDir;
                    parameters[StageParams.MediaDir] = mediaDir;
                    parameters[StageParams.WimOut] = wimOut;
                    break;
                case ServicingOpcode.BuildIso:
                    parameters[StageParams.OutputIso] = outputIso;
                    parameters[StageParams.MediaDir] = mediaDir;
                    parameters[StageParams.WimOut] = wimOut;
                    break;
            }

            resolved.Add(new ServicingStage(stage.Opcode, parameters));
        }

        StagesFile stagesFile = new(
            BuildPlan.StagesSchemaVersion,
            resolved.Select(s => new StageFile(s.Opcode.ToString(), s.Parameters)).ToArray());
        File.WriteAllText(
            Path.Combine(run.WorkDirectory, "stages.json"),
            JsonSerializer.Serialize(stagesFile, ServicingJsonContext.Default.StagesFile));

        return Result.Ok<List<ServicingStage>, ServicingFailure>(resolved);
    }

    private static Result<string, ServicingFailure> StageSetupCompleteScript(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "SetupComplete.cmd");
        string? source = FindSetupCompleteScript();
        if (source is null)
        {
            return Result.Fail<string, ServicingFailure>(
                new ServicingFailure(
                    "servicing.setupComplete.missing",
                    "payload/scripts/SetupComplete.cmd not found."));
        }

        File.Copy(source, dest, overwrite: true);
        return Result.Ok<string, ServicingFailure>(dest);
    }

    private static Result<string, ServicingFailure> StageSupervisorBinary(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "Supervisor.exe");
        string? published = FindPublishedSupervisor();
        if (published is null)
        {
            return Result.Fail<string, ServicingFailure>(
                new ServicingFailure(
                    "servicing.supervisor.missing",
                    "Published Supervisor not found. Run: just publish-provisioning"));
        }

        File.Copy(published, dest, overwrite: true);
        return Result.Ok<string, ServicingFailure>(dest);
    }

    private static string? FindSetupCompleteScript()
    {
        string candidate = Path.Combine(RepoRootGuess(), "payload", "scripts", "SetupComplete.cmd");
        return File.Exists(candidate) ? candidate : null;
    }

    private static string? FindPublishedSupervisor()
    {
        string[] candidates =
        [
            Path.Combine(RepoRootGuess(), "artifacts", "provisioning", "WinMint.Provisioning.exe"),
            Path.Combine(AppContext.BaseDirectory, "WinMint.Provisioning.exe"),
        ];
        return candidates.FirstOrDefault(File.Exists);
    }

    private static string RepoRootGuess()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "justfile"))
                || File.Exists(Path.Combine(dir, "Justfile")))
            {
                return dir;
            }

            DirectoryInfo? parent = Directory.GetParent(dir);
            if (parent is null)
            {
                break;
            }

            dir = parent.FullName;
        }

        return Directory.GetCurrentDirectory();
    }
}

internal sealed record JobsFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("jobs")] JobFile[] Jobs);

internal sealed record JobFile(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("kind")] string Kind);

internal sealed record BundleFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("supervisorPath")] string SupervisorPath,
    [property: JsonPropertyName("username")] string Username,
    [property: JsonPropertyName("password")] string Password,
    [property: JsonPropertyName("dmaEnabled")] bool DmaEnabled,
    [property: JsonPropertyName("settle")] SettleFile? Settle,
    [property: JsonPropertyName("jobIds")] string[] JobIds);

internal sealed record SettleFile(
    [property: JsonPropertyName("locale")] string Locale,
    [property: JsonPropertyName("geoId")] int GeoId,
    [property: JsonPropertyName("timeZoneId")] string TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool LocationServicesEnabled);

internal sealed record StagesFile(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("stages")] StageFile[] Stages);

internal sealed record StageFile(
    [property: JsonPropertyName("opcode")] string Opcode,
    [property: JsonPropertyName("parameters")] IReadOnlyDictionary<string, string> Parameters);

[JsonSerializable(typeof(JobsFile))]
[JsonSerializable(typeof(BundleFile))]
[JsonSerializable(typeof(StagesFile))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class ServicingJsonContext : JsonSerializerContext;
