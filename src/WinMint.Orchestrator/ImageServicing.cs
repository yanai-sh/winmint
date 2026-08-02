using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

public static class ImageServicing
{
    public const string EvidenceSchemaVersion = "winmint.image.evidence/v1";
    public const string BundleSchemaVersion = "winmint.provisioning.bundle/v1";

    /// <summary>Guest path stamped into Winlogon Shell (offline); Machine setup verifies the same path.</summary>
    public const string ShellStampGuestPath = @"C:\Windows\WinMint\Supervisor.exe";

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

        IReadOnlyList<ServicingStage> stages = Materialize(plan, run);

        Result<ImageEvidence, ServicingFailure> outcome = runner.Execute(run.WorkDirectory, stages, run, plan, ct);
        // Invariant: never delete workdir on failure (or success) — caller owns lifetime.
        return outcome;
    }

    private static List<ServicingStage> Materialize(BuildArtifacts plan, ServicingRun run)
    {
        string payloadDir = Path.Combine(run.WorkDirectory, "payload");
        string unattendPath = Path.Combine(run.WorkDirectory, "unattend.xml");
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

        string setupComplete = """
            @echo off
            rem WinMint SetupComplete — Machine setup entry (ticket 02 staging; behaviour in ticket 03+)
            "%SystemRoot%\WinMint\Supervisor.exe" --machine-setup
            if errorlevel 1 exit /b 1
            """;
        File.WriteAllText(Path.Combine(payloadDir, "SetupComplete.cmd"), setupComplete);

        StageSupervisorBinary(payloadDir);

        List<ServicingStage> resolved = new(plan.Stages.Stages.Count);
        foreach (ServicingStage stage in plan.Stages.Stages)
        {
            Dictionary<string, string> parameters = new(stage.Parameters, StringComparer.Ordinal);
            switch (stage.Opcode)
            {
                case ServicingOpcode.MountInstallWim:
                    parameters["sourceIso"] = run.SourceIsoPath;
                    parameters["mountDir"] = Path.Combine(run.WorkDirectory, "mount");
                    break;
                case ServicingOpcode.StagePayload:
                    parameters["payloadDir"] = payloadDir;
                    parameters["mountDir"] = Path.Combine(run.WorkDirectory, "mount");
                    break;
                case ServicingOpcode.InjectUnattend:
                    parameters["unattendPath"] = unattendPath;
                    parameters["mountDir"] = Path.Combine(run.WorkDirectory, "mount");
                    break;
                case ServicingOpcode.StampOfflineShell:
                    parameters["shellTarget"] = ShellStampGuestPath;
                    parameters["mountDir"] = Path.Combine(run.WorkDirectory, "mount");
                    break;
                case ServicingOpcode.ExportWim:
                    parameters["mountDir"] = Path.Combine(run.WorkDirectory, "mount");
                    parameters["wimOut"] = Path.Combine(run.WorkDirectory, "install.wim");
                    break;
                case ServicingOpcode.BuildIso:
                    parameters["outputIso"] = run.OutputIsoPath ?? Path.Combine(run.WorkDirectory, "out.iso");
                    parameters["wimOut"] = Path.Combine(run.WorkDirectory, "install.wim");
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

        return resolved;
    }

    private static void StageSupervisorBinary(string payloadDir)
    {
        string dest = Path.Combine(payloadDir, "Supervisor.exe");
        string? published = FindPublishedSupervisor();
        if (published is not null)
        {
            File.Copy(published, dest, overwrite: true);
            return;
        }

        // ponytail: marker placeholder until `just publish-provisioning` — elevated StagePayload copies this path into the image.
        File.WriteAllText(dest + ".missing", "Run: just publish-provisioning");
        File.WriteAllBytes(dest, System.Text.Encoding.UTF8.GetBytes("WinMint-Supervisor-stub"));
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
            if (File.Exists(Path.Combine(dir, "justfile")))
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
