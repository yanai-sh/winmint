using System.CommandLine;
using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Orchestrator;

namespace WinMint.Cli;

internal static class Program
{
    private static int Main(string[] args)
    {
        Argument<FileInfo> profileArgument = new("profile")
        {
            Description = "Path to a winmint.profile/v1 JSON document.",
        };

        Option<DirectoryInfo> outOption = new("--out", "-o")
        {
            Description = "Directory to write plan artifacts into.",
            Required = true,
        };

        Command validateCommand = new("validate", "Parse and plan a Profile; write nothing.")
        {
            profileArgument,
        };
        validateCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            return RunValidate(profilePath);
        });

        Command planCommand = new("plan", "Parse and plan a Profile; emit plan artifacts.")
        {
            profileArgument,
            outOption,
        };
        planCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            DirectoryInfo outDir = parseResult.GetValue(outOption)!;
            return RunPlan(profilePath, outDir);
        });

        RootCommand root = new("WinMint — Profile validate / plan (Smoke ticket 01)")
        {
            validateCommand,
            planCommand,
        };

        return root.Parse(args).Invoke();
    }

    private static int RunValidate(FileInfo profilePath)
    {
        if (!TryLoadArtifacts(profilePath, out _, out int exit))
        {
            return exit;
        }

        Console.WriteLine("Profile OK; plan OK.");
        return 0;
    }

    private static int RunPlan(FileInfo profilePath, DirectoryInfo outDir)
    {
        if (!TryLoadArtifacts(profilePath, out BuildArtifacts? artifacts, out int exit))
        {
            return exit;
        }

        Directory.CreateDirectory(outDir.FullName);
        PlanArtifactWriter.Write(outDir.FullName, artifacts!);
        Console.WriteLine($"Wrote plan artifacts to {outDir.FullName}");
        return 0;
    }

    private static bool TryLoadArtifacts(FileInfo profilePath, out BuildArtifacts? artifacts, out int exitCode)
    {
        artifacts = null;
        if (!profilePath.Exists)
        {
            Console.Error.WriteLine($"Profile not found: {profilePath.FullName}");
            exitCode = 1;
            return false;
        }

        byte[] utf8 = File.ReadAllBytes(profilePath.FullName);
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        if (!parsed.IsOk)
        {
            foreach (DocumentError issue in parsed.Error.Issues)
            {
                Console.Error.WriteLine($"{issue.Code}: {issue.Message}" + (issue.Path is null ? "" : $" ({issue.Path})"));
            }

            exitCode = 1;
            return false;
        }

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        if (!planned.IsOk)
        {
            Console.Error.WriteLine($"{planned.Error.Code}: {planned.Error.Message}");
            exitCode = 1;
            return false;
        }

        artifacts = planned.Value;
        exitCode = 0;
        return true;
    }
}

internal static class PlanArtifactWriter
{
    public static void Write(string directory, BuildArtifacts artifacts)
    {
        File.WriteAllText(Path.Combine(directory, "unattend.xml"), artifacts.Unattend.Xml);

        JobsDump jobs = new(artifacts.Jobs.SchemaVersion, artifacts.Jobs.Jobs.Select(j => new JobDump(j.Id, j.Kind)).ToArray());
        File.WriteAllText(
            Path.Combine(directory, "jobs.json"),
            JsonSerializer.Serialize(jobs, CliJsonContext.Default.JobsDump));

        PayloadDump payload = new(artifacts.Payload.Entries.ToArray());
        File.WriteAllText(
            Path.Combine(directory, "payload.json"),
            JsonSerializer.Serialize(payload, CliJsonContext.Default.PayloadDump));

        StagesDump stages = new(
            BuildPlan.StagesSchemaVersion,
            artifacts.Stages.Stages.Select(s => new StageDump(s.Opcode.ToString(), s.Parameters)).ToArray());
        File.WriteAllText(
            Path.Combine(directory, "stages.json"),
            JsonSerializer.Serialize(stages, CliJsonContext.Default.StagesDump));

        DmaDump dma = new(
            artifacts.Dma.Enabled,
            artifacts.Dma.Settle is null
                ? null
                : new SettleDump(
                    artifacts.Dma.Settle.Locale,
                    artifacts.Dma.Settle.GeoId,
                    artifacts.Dma.Settle.TimeZoneId,
                    artifacts.Dma.Settle.LocationServicesEnabled));
        File.WriteAllText(
            Path.Combine(directory, "dma.json"),
            JsonSerializer.Serialize(dma, CliJsonContext.Default.DmaDump));

        ManifestDump manifest = new(artifacts.Manifest.ImageQuality.ToString());
        File.WriteAllText(
            Path.Combine(directory, "manifest.json"),
            JsonSerializer.Serialize(manifest, CliJsonContext.Default.ManifestDump));
    }
}

internal sealed record JobsDump(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("jobs")] JobDump[] Jobs);

internal sealed record JobDump(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("kind")] string Kind);

internal sealed record PayloadDump(
    [property: JsonPropertyName("entries")] string[] Entries);

internal sealed record StagesDump(
    [property: JsonPropertyName("schemaVersion")] string SchemaVersion,
    [property: JsonPropertyName("stages")] StageDump[] Stages);

internal sealed record StageDump(
    [property: JsonPropertyName("opcode")] string Opcode,
    [property: JsonPropertyName("parameters")] IReadOnlyDictionary<string, string> Parameters);

internal sealed record DmaDump(
    [property: JsonPropertyName("enabled")] bool Enabled,
    [property: JsonPropertyName("settle")] SettleDump? Settle);

internal sealed record SettleDump(
    [property: JsonPropertyName("locale")] string Locale,
    [property: JsonPropertyName("geoId")] int GeoId,
    [property: JsonPropertyName("timeZoneId")] string TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool LocationServicesEnabled);

internal sealed record ManifestDump(
    [property: JsonPropertyName("imageQuality")] string ImageQuality);

[JsonSerializable(typeof(JobsDump))]
[JsonSerializable(typeof(PayloadDump))]
[JsonSerializable(typeof(StagesDump))]
[JsonSerializable(typeof(DmaDump))]
[JsonSerializable(typeof(ManifestDump))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class CliJsonContext : JsonSerializerContext;
