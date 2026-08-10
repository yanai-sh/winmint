using System.CommandLine;
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

        Option<string?> imageArchitectureOption = new("--image-architecture")
        {
            Description = "Target image CPU architecture for package validation (default arm64).",
        };

        Option<bool> packageAuditStrictOption = new("--package-audit-strict")
        {
            Description = "Fail closed when native ARM64 audit finds x64/emulated winget GUI binaries.",
        };

        Option<bool> packageStrictOption = new("--package-strict")
        {
            Description = "Fail closed when winget/scoop package jobs fail (harness/metal). Default best-effort.",
        };

        Option<bool> includeSmokeStubsOption = new("--include-smoke-stubs")
        {
            Description = "Include smoke.stub.* FirstLogon jobs (Smoke/acceptance harness). Default off.",
        };

        Command validateCommand = new("validate", "Parse and plan a Profile; write nothing.")
        {
            profileArgument,
            imageQualityOption,
            imageArchitectureOption,
            packageAuditStrictOption,
            packageStrictOption,
            includeSmokeStubsOption,
        };
        validateCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            return RunValidate(
                profilePath,
                parseResult.GetValue(imageQualityOption)!,
                parseResult.GetValue(imageArchitectureOption),
                parseResult.GetValue(packageAuditStrictOption),
                parseResult.GetValue(packageStrictOption),
                parseResult.GetValue(includeSmokeStubsOption));
        });

        Command planCommand = new("plan", "Parse and plan a Profile; emit plan artifacts.")
        {
            profileArgument,
            outOption,
            imageQualityOption,
            imageArchitectureOption,
            packageAuditStrictOption,
            packageStrictOption,
            includeSmokeStubsOption,
        };
        planCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            DirectoryInfo outDir = parseResult.GetValue(outOption)!;
            return RunPlan(
                profilePath,
                outDir,
                parseResult.GetValue(imageQualityOption)!,
                parseResult.GetValue(imageArchitectureOption),
                parseResult.GetValue(packageAuditStrictOption),
                parseResult.GetValue(packageStrictOption),
                parseResult.GetValue(includeSmokeStubsOption));
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
            imageArchitectureOption,
            packageAuditStrictOption,
            packageStrictOption,
            includeSmokeStubsOption,
        };
        buildCommand.SetAction(parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            FileInfo iso = parseResult.GetValue(isoOption)!;
            DirectoryInfo work = parseResult.GetValue(workOption)!;
            FileInfo? outIso = parseResult.GetValue(outIsoOption);
            int? wimIndex = parseResult.GetValue(wimIndexOption);
            bool reuseMedia = parseResult.GetValue(reuseMediaOption);
            return RunBuild(
                profilePath,
                iso,
                work,
                outIso,
                wimIndex,
                reuseMedia,
                parseResult.GetValue(imageQualityOption)!,
                parseResult.GetValue(imageArchitectureOption),
                parseResult.GetValue(packageAuditStrictOption),
                parseResult.GetValue(packageStrictOption),
                parseResult.GetValue(includeSmokeStubsOption));
        });

        RootCommand root = new("WinMint — Profile plan and ImageServicing build")
        {
            validateCommand,
            planCommand,
            buildCommand,
        };

        return root.Parse(args).Invoke();
    }

    private static int RunValidate(
        FileInfo profilePath,
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        bool packageStrict,
        bool includeSmokeStubs)
    {
        if (!TryBuildRunOptions(
                imageQuality,
                imageArchitecture,
                packageAuditStrict,
                packageStrict,
                includeSmokeStubs,
                out RunOptions run,
                out int exit))
        {
            return exit;
        }

        if (!TryLoadArtifacts(profilePath, out _, out exit, run))
        {
            return exit;
        }

        Console.WriteLine("Profile OK; plan OK.");
        return 0;
    }

    private static int RunPlan(
        FileInfo profilePath,
        DirectoryInfo outDir,
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        bool packageStrict,
        bool includeSmokeStubs)
    {
        if (!TryBuildRunOptions(
                imageQuality,
                imageArchitecture,
                packageAuditStrict,
                packageStrict,
                includeSmokeStubs,
                out RunOptions run,
                out int exit))
        {
            return exit;
        }

        if (!TryLoadArtifacts(profilePath, out BuildArtifacts? artifacts, out exit, run))
        {
            return exit;
        }

        Directory.CreateDirectory(outDir.FullName);
        WritePlanArtifacts(outDir.FullName, artifacts!);
        Console.WriteLine($"Wrote plan artifacts to {outDir.FullName}");
        WritePlanHonesty(artifacts!);
        return 0;
    }

    private static int RunBuild(
        FileInfo profilePath,
        FileInfo iso,
        DirectoryInfo work,
        FileInfo? outIso,
        int? wimIndex,
        bool reuseMedia,
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        bool packageStrict,
        bool includeSmokeStubs)
    {
        if (!TryBuildRunOptions(
                imageQuality,
                imageArchitecture,
                packageAuditStrict,
                packageStrict,
                includeSmokeStubs,
                out RunOptions planRun,
                out int exit))
        {
            return exit;
        }

        if (!TryLoadArtifacts(
                profilePath,
                out BuildArtifacts? artifacts,
                out exit,
                planRun with
                {
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

        WritePlanHonesty(artifacts!);

        ServicingRun servicingRun = new(
            SourceIsoPath: iso.FullName,
            WorkDirectory: work.FullName,
            OutputIsoPath: outIso?.FullName ?? Path.Combine(work.FullName, "out.iso"),
            WimIndex: wimIndex,
            ReuseMedia: reuseMedia);

        Result<ImageEvidence, Failure> applied = ImageServicing.Apply(artifacts!, servicingRun);
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

    private static bool TryBuildRunOptions(
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        bool packageStrict,
        bool includeSmokeStubs,
        out RunOptions run,
        out int exitCode)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out exitCode))
        {
            run = new RunOptions();
            return false;
        }

        run = new RunOptions
        {
            ImageQuality = lane,
            ImageArchitecture = imageArchitecture,
            PackageAuditStrict = packageAuditStrict,
            PackageStrict = packageStrict,
            IncludeSmokeStubs = includeSmokeStubs,
        };
        exitCode = 0;
        return true;
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

        Result<Profile, DocumentErrors> parsed = ProfileFile.TryLoad(profilePath.FullName);
        if (!parsed.IsOk)
        {
            foreach (DocumentError issue in parsed.Error.Issues)
            {
                Console.Error.WriteLine($"{issue.Code}: {issue.Message}" + (issue.Path is null ? "" : $" ({issue.Path})"));
            }

            exitCode = 1;
            return false;
        }

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value, run);
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

        File.WriteAllText(
            Path.Combine(directory, "jobs.json"),
            BuildPlan.SerializeJobsDump(artifacts.Jobs));
        File.WriteAllText(
            Path.Combine(directory, "stages.json"),
            BuildPlan.SerializeStagesDump(artifacts.Stages));
        File.WriteAllText(
            Path.Combine(directory, "manifest.json"),
            BuildPlan.SerializeManifestDump(artifacts.Manifest));
    }

    private static void WritePlanHonesty(BuildArtifacts artifacts)
    {
        Console.WriteLine($"Lane: {artifacts.Manifest.ImageQuality}");
        string honesty = BuildPlan.FormatPlanHonesty(
            artifacts.Manifest,
            artifacts.Account.RequireWifiDuringOobe);
        foreach (string line in honesty.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            if (line.StartsWith("Warning:", StringComparison.Ordinal))
            {
                Console.Error.WriteLine(line);
            }
            else if (line.Length > 0)
            {
                Console.WriteLine(line);
            }
        }
    }
}
