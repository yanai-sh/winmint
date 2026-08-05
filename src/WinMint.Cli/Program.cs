using System.CommandLine;
using System.Text.Json;
using System.Text.Json.Nodes;
using WinMint.Orchestrator;

namespace WinMint.Cli;

internal static class Program
{
    private static readonly JsonSerializerOptions IndentedJson = new() { WriteIndented = true };

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

        Command buildCommand = new("build", "Plan a Profile and apply ImageServicing (one elevated RunPlan).")
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
            return RunBuild(profilePath, iso, work, outIso, wimIndex, reuseMedia, imageQuality);
        });

        RootCommand root = new("WinMint — Profile plan and ImageServicing build")
        {
            validateCommand,
            planCommand,
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
        WritePlanArtifacts(outDir.FullName, artifacts!);
        Console.WriteLine($"Wrote plan artifacts to {outDir.FullName}");
        Console.WriteLine($"Lane: {artifacts!.Manifest.ImageQuality}");
        return 0;
    }

    private static int RunBuild(
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
                "Warning: ImageQuality=Release uses compression=max + cleanup=full — prefer Test for iterative builds.");
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
        if (Enum.TryParse(raw, true, out lane) && Enum.IsDefined(lane))
        {
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

    private static void WritePlanArtifacts(string directory, BuildArtifacts artifacts)
    {
        File.WriteAllText(Path.Combine(directory, "unattend.xml"), artifacts.Unattend.Xml);

        WriteJson(
            directory,
            "jobs.json",
            new JsonObject
            {
                ["schemaVersion"] = artifacts.Jobs.SchemaVersion,
                ["jobs"] = new JsonArray(
                    artifacts.Jobs.Jobs.Select(static j => (JsonNode)new JsonObject
                    {
                        ["id"] = j.Id,
                        ["kind"] = j.Kind,
                        ["needsReboot"] = j.NeedsReboot,
                        ["packageId"] = j.PackageId,
                    }).ToArray()),
            });

        WriteJson(
            directory,
            "payload.json",
            new JsonObject
            {
                ["entries"] = new JsonArray(artifacts.Payload.Entries.Select(static e => (JsonNode)e).ToArray()),
            });

        WriteJson(
            directory,
            "stages.json",
            new JsonObject
            {
                ["schemaVersion"] = BuildPlan.StagesSchemaVersion,
                ["stages"] = new JsonArray(
                    artifacts.Stages.Stages.Select(static s => (JsonNode)new JsonObject
                    {
                        ["opcode"] = s.Opcode.ToString(),
                        ["parameters"] = new JsonObject(
                            s.Parameters.Select(static kv =>
                                KeyValuePair.Create<string, JsonNode?>(kv.Key, kv.Value))),
                    }).ToArray()),
            });

        JsonObject dma = new() { ["enabled"] = artifacts.Dma.Enabled };
        if (artifacts.Dma.Settle is { } settle)
        {
            dma["settle"] = new JsonObject
            {
                ["locale"] = settle.Locale,
                ["geoId"] = settle.GeoId,
                ["timeZoneId"] = settle.TimeZoneId,
                ["locationServicesEnabled"] = settle.LocationServicesEnabled,
            };
        }
        else
        {
            dma["settle"] = null;
        }

        WriteJson(directory, "dma.json", dma);
        WriteJson(
            directory,
            "manifest.json",
            new JsonObject { ["imageQuality"] = artifacts.Manifest.ImageQuality.ToString() });
    }

    private static void WriteJson(string directory, string name, JsonNode node) =>
        File.WriteAllText(Path.Combine(directory, name), node.ToJsonString(IndentedJson));
}
