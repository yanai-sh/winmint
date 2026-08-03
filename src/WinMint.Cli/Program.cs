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

        Option<FileInfo> isoOption = new("--iso")
        {
            Description = "Path to the user-supplied Source ISO.",
            Required = true,
        };

        Option<DirectoryInfo> workOption = new("--work")
        {
            Description = "Servicing work directory (preserved on failure).",
            Required = true,
        };

        Option<FileInfo?> outIsoOption = new("--out-iso")
        {
            Description = "Output ISO path (defaults to <work>/out.iso).",
        };

        Option<int?> wimIndexOption = new("--wim-index")
        {
            Description = "install.wim index (default: 3 = Windows 11 Pro on consumer multi-edition ISOs).",
        };

        Option<bool> reuseMediaOption = new("--reuse-media")
        {
            Description = "Skip ISO copy/export; require existing single-image media under --work (fail closed if missing).",
        };

        Option<string> imageQualityOption = new("--image-quality")
        {
            Description = "Image quality lane: Test (default) or Release.",
            DefaultValueFactory = _ => "Test",
        };

        Command validateCommand = new("validate", "Parse and plan a Profile; write nothing.")
        {
            profileArgument,
            imageQualityOption,
        };
        validateCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            string imageQuality = parseResult.GetValue(imageQualityOption)!;
            return RunValidate(profilePath, imageQuality);
        });

        Command planCommand = new("plan", "Parse and plan a Profile; emit plan artifacts.")
        {
            profileArgument,
            outOption,
            imageQualityOption,
        };
        planCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            DirectoryInfo outDir = parseResult.GetValue(outOption)!;
            string imageQuality = parseResult.GetValue(imageQualityOption)!;
            return RunPlan(profilePath, outDir, imageQuality);
        });

        Command applyCommand = new("apply", "Plan a Profile and apply ImageServicing (one elevated RunPlan).")
        {
            profileArgument,
            isoOption,
            workOption,
            outIsoOption,
            wimIndexOption,
            reuseMediaOption,
            imageQualityOption,
        };
        applyCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            FileInfo iso = parseResult.GetValue(isoOption)!;
            DirectoryInfo work = parseResult.GetValue(workOption)!;
            FileInfo? outIso = parseResult.GetValue(outIsoOption);
            int? wimIndex = parseResult.GetValue(wimIndexOption);
            bool reuseMedia = parseResult.GetValue(reuseMediaOption);
            string imageQuality = parseResult.GetValue(imageQualityOption)!;
            return RunApply(profilePath, iso, work, outIso, wimIndex, reuseMedia, imageQuality);
        });

        Command buildCommand = new("build", "Plan + apply (same path as apply; preferred product verb).")
        {
            profileArgument,
            isoOption,
            workOption,
            outIsoOption,
            wimIndexOption,
            reuseMediaOption,
            imageQualityOption,
        };
        buildCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            FileInfo iso = parseResult.GetValue(isoOption)!;
            DirectoryInfo work = parseResult.GetValue(workOption)!;
            FileInfo? outIso = parseResult.GetValue(outIsoOption);
            int? wimIndex = parseResult.GetValue(wimIndexOption);
            bool reuseMedia = parseResult.GetValue(reuseMediaOption);
            string imageQuality = parseResult.GetValue(imageQualityOption)!;
            return RunApply(profilePath, iso, work, outIso, wimIndex, reuseMedia, imageQuality);
        });

        RootCommand root = new("WinMint — Profile plan and ImageServicing apply")
        {
            validateCommand,
            planCommand,
            applyCommand,
            buildCommand,
        };

        return root.Parse(args).Invoke();
    }

    private static int RunValidate(FileInfo profilePath, string imageQuality)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out int exit))
        {
            return exit;
        }

        if (!TryLoadArtifacts(profilePath, out _, out exit, new RunOptions { ImageQuality = lane }))
        {
            return exit;
        }

        Console.WriteLine("Profile OK; plan OK.");
        return 0;
    }

    private static int RunPlan(FileInfo profilePath, DirectoryInfo outDir, string imageQuality)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out int exit))
        {
            return exit;
        }

        if (!TryLoadArtifacts(profilePath, out BuildArtifacts? artifacts, out exit, new RunOptions { ImageQuality = lane }))
        {
            return exit;
        }

        Directory.CreateDirectory(outDir.FullName);
        PlanArtifactWriter.Write(outDir.FullName, artifacts!);
        Console.WriteLine($"Wrote plan artifacts to {outDir.FullName}");
        Console.WriteLine($"Lane: {artifacts!.Manifest.ImageQuality}");
        return 0;
    }

    private static int RunApply(
        FileInfo profilePath,
        FileInfo iso,
        DirectoryInfo work,
        FileInfo? outIso,
        int? wimIndex,
        bool reuseMedia,
        string imageQuality)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out int exit))
        {
            return exit;
        }

        if (!TryLoadArtifacts(
                profilePath,
                out BuildArtifacts? artifacts,
                out exit,
                new RunOptions
                {
                    ImageQuality = lane,
                    SourceIsoPath = iso.FullName,
                    OutputIsoPath = outIso?.FullName,
                }))
        {
            return exit;
        }

        if (artifacts!.Manifest.ImageQuality == ImageQualityLane.Release)
        {
            Console.Error.WriteLine(
                "Warning: ImageQuality=Release uses compression=max + cleanup=full — prefer Test for iterative Apply.");
        }

        ServicingRun run = new(
            SourceIsoPath: iso.FullName,
            WorkDirectory: work.FullName,
            OutputIsoPath: outIso?.FullName ?? Path.Combine(work.FullName, "out.iso"),
            WimIndex: wimIndex,
            ReuseMedia: reuseMedia);

        Result<ImageEvidence, ServicingFailure> applied = ImageServicing.Apply(artifacts!, run);
        if (!applied.IsOk)
        {
            Console.Error.WriteLine($"{applied.Error.Code}: {applied.Error.Message}");
            Console.Error.WriteLine($"Work directory preserved: {work.FullName}");
            return 1;
        }

        Console.WriteLine($"Image OK: {applied.Value.OutputIsoPath}");
        Console.WriteLine($"Shell stamp: {applied.Value.ShellStampTargetPath}");
        Console.WriteLine($"Lane: {applied.Value.Lane}");
        return 0;
    }

    private static bool TryParseImageQuality(string raw, out ImageQualityLane lane, out int exitCode)
    {
        if (string.Equals(raw, "Test", StringComparison.OrdinalIgnoreCase))
        {
            lane = ImageQualityLane.Test;
            exitCode = 0;
            return true;
        }

        if (string.Equals(raw, "Release", StringComparison.OrdinalIgnoreCase))
        {
            lane = ImageQualityLane.Release;
            exitCode = 0;
            return true;
        }

        Console.Error.WriteLine($"Unsupported --image-quality '{raw}' (expected Test|Release).");
        lane = ImageQualityLane.Test;
        exitCode = 1;
        return false;
    }

    private static bool TryLoadArtifacts(
        FileInfo profilePath,
        out BuildArtifacts? artifacts,
        out int exitCode,
        RunOptions? run = null)
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

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value, run);
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
