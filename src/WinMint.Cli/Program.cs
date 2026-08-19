using System.CommandLine;
using System.CommandLine.Parsing;

using Microsoft.Extensions.Logging;

using WinMint.Orchestrator;

namespace WinMint.Cli;

internal static class Program
{
    private static readonly ILogger Log = ConsoleCliLogger.Instance;

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
            Description = "Output ISO path (defaults to <work>/winmint_{profile}_{lane}_{yyyyMMdd-HHmmss}.iso).",
        };

        Option<int?> wimIndexOption = new("--wim-index")
        {
            Description = "install.wim index (default: 3 = Windows 11 Pro on consumer multi-edition ISOs).",
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
            Description = "Force package jobs fail closed; otherwise Test is best-effort and Release is strict.",
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
                ParsePackageStrictOverride(parseResult, packageStrictOption),
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
                ParsePackageStrictOverride(parseResult, packageStrictOption),
                parseResult.GetValue(includeSmokeStubsOption));
        });

        Command buildCommand = new("build", "Plan a Profile and apply ImageServicing (one elevated Invoke-ServicingPlan).")
        {
            profileArgument,
            isoOption,
            workOption,
            outIsoOption,
            wimIndexOption,
            imageQualityOption,
            imageArchitectureOption,
            packageAuditStrictOption,
            packageStrictOption,
            includeSmokeStubsOption,
        };
        buildCommand.SetAction(async parseResult =>
        {
            FileInfo profilePath = parseResult.GetValue(profileArgument)!;
            FileInfo iso = parseResult.GetValue(isoOption)!;
            DirectoryInfo work = parseResult.GetValue(workOption)!;
            FileInfo? outIso = parseResult.GetValue(outIsoOption);
            int? wimIndex = parseResult.GetValue(wimIndexOption);
            return await RunBuildAsync(
                profilePath,
                iso,
                work,
                outIso,
                wimIndex,
                parseResult.GetValue(imageQualityOption)!,
                parseResult.GetValue(imageArchitectureOption),
                parseResult.GetValue(packageAuditStrictOption),
                ParsePackageStrictOverride(parseResult, packageStrictOption),
                parseResult.GetValue(includeSmokeStubsOption));
        });

        Command packagesCheckCommand = new(
            "packages-check",
            "Refresh the live ARM64 package catalog proof.");
        packagesCheckCommand.SetAction(
            async (_, ct) => await RunPackagesCheckAsync(ct).ConfigureAwait(false));

        RootCommand root = new("WinMint — Profile plan and ImageServicing build")
        {
            validateCommand,
            planCommand,
            buildCommand,
            packagesCheckCommand,
        };

        return root.Parse(args).Invoke();
    }

    private static async Task<int> RunPackagesCheckAsync(CancellationToken ct)
    {
        string toolkitRoot;
        try
        {
            toolkitRoot = ToolkitRoot.FindRoot("config", "packages.json");
        }
        catch (DirectoryNotFoundException ex)
        {
            CliLog.Failure(Log, "packages.proof.toolkitMissing", ex.Message);
            return 1;
        }

        Result<PackagesProofRefreshResult, Failure> refreshed =
            await PackagesProof.RefreshAsync(toolkitRoot, ct).ConfigureAwait(false);
        if (!refreshed.IsOk)
        {
            CliLog.Failure(Log, refreshed.Error.Code, refreshed.Error.Message);
            return 1;
        }

        CliLog.PackagesProofRefreshed(
            Log,
            refreshed.Value.EntryCount,
            refreshed.Value.ProofPath);
        return 0;
    }

    private static int RunValidate(
        FileInfo profilePath,
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        PackageStrictOverride packageStrict,
        bool includeSmokeStubs)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out int exit))
        {
            return exit;
        }

        if (!TryLoadPlan(
                profilePath,
                out _,
                out exit,
                new HostComposeOptions(
                    ImageQuality: lane,
                    ImageArchitecture: imageArchitecture,
                    PackageAuditStrict: packageAuditStrict,
                    PackageStrict: packageStrict,
                    IncludeSmokeStubs: includeSmokeStubs)))
        {
            return exit;
        }

        CliLog.ProfileOk(Log);
        return 0;
    }

    private static int RunPlan(
        FileInfo profilePath,
        DirectoryInfo outDir,
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        PackageStrictOverride packageStrict,
        bool includeSmokeStubs)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out int exit))
        {
            return exit;
        }

        if (!TryLoadPlan(
                profilePath,
                out HostPlan? plan,
                out exit,
                new HostComposeOptions(
                    ImageQuality: lane,
                    ImageArchitecture: imageArchitecture,
                    PackageAuditStrict: packageAuditStrict,
                    PackageStrict: packageStrict,
                    IncludeSmokeStubs: includeSmokeStubs)))
        {
            return exit;
        }

        Result<Unit, Failure> exported = HostCompile.ExportPlan(plan!, outDir.FullName);
        if (!exported.IsOk)
        {
            CliLog.Failure(Log, exported.Error.Code, exported.Error.Message);
            return 1;
        }
        CliLog.WrotePlanArtifacts(Log, outDir.FullName);
        WritePlanHonesty(plan!.Review);
        return 0;
    }

    private static async Task<int> RunBuildAsync(
        FileInfo profilePath,
        FileInfo iso,
        DirectoryInfo work,
        FileInfo? outIso,
        int? wimIndex,
        string imageQuality,
        string? imageArchitecture,
        bool packageAuditStrict,
        PackageStrictOverride packageStrict,
        bool includeSmokeStubs)
    {
        if (!TryParseImageQuality(imageQuality, out ImageQualityLane lane, out int exit))
        {
            return exit;
        }

        Result<HostComposition, HostComposeError> composed = await HostCompile.ComposeFileAsync(
                profilePath.FullName,
                new HostComposeOptions(
                    iso.FullName,
                    lane,
                    work.FullName,
                    outIso?.FullName,
                    wimIndex,
                    packageStrict,
                    packageAuditStrict,
                    includeSmokeStubs,
                    imageArchitecture))
            .ConfigureAwait(false);
        if (!composed.IsOk)
        {
            if (composed.Error.Documents is { } documents)
            {
                foreach (DocumentError issue in documents)
                {
                    string pathSuffix = issue.Path is null ? "" : $" ({issue.Path})";
                    CliLog.DocumentIssue(Log, issue.Code, issue.Message, pathSuffix);
                }
            }
            else
            {
                CliLog.Failure(Log, composed.Error.Code, composed.Error.Message);
            }
            CliLog.WorkPreserved(Log, work.FullName);
            return 1;
        }

        HostComposition composition = composed.Value;
        if (composition.Review.ImageQuality == ImageQualityLane.Release)
        {
            CliLog.ReleaseLaneWarning(Log);
        }

        WritePlanHonesty(composition.Review);

        Result<ImageEvidence, Failure> applied =
            await HostCompile.ApplyAsync(composition).ConfigureAwait(false);
        if (!applied.IsOk)
        {
            CliLog.Failure(Log, applied.Error.Code, applied.Error.Message);
            CliLog.WorkPreserved(Log, work.FullName);
            return 1;
        }

        CliLog.ImageOk(Log, applied.Value.OutputIsoPath);
        CliLog.ShellStamp(Log, applied.Value.ShellStampTargetPath);
        CliLog.Lane(Log, applied.Value.Lane);
        return 0;
    }

    internal static PackageStrictOverride ParsePackageStrictOverride(
        ParseResult parseResult,
        Option<bool> option)
    {
        OptionResult? result = parseResult.GetResult(option);
        if (result is null || result.Implicit)
        {
            return PackageStrictOverride.FromLane;
        }

        return result.GetValueOrDefault<bool>()
            ? PackageStrictOverride.Force
            : PackageStrictOverride.Suppress;
    }

    private static bool TryParseImageQuality(string raw, out ImageQualityLane lane, out int exitCode)
    {
        if (Enum.TryParse(raw, true, out lane) && Enum.IsDefined(lane))
        {
            exitCode = 0;
            return true;
        }

        CliLog.UnsupportedImageQuality(Log, raw);
        lane = ImageQualityLane.Test;
        exitCode = 1;
        return false;
    }

    private static bool TryLoadPlan(
        FileInfo profilePath,
        out HostPlan? plan,
        out int exitCode,
        HostComposeOptions? options = null)
    {
        plan = null;
        if (!profilePath.Exists)
        {
            CliLog.ProfileNotFound(Log, profilePath.FullName);
            exitCode = 1;
            return false;
        }

        Result<Profile, IReadOnlyList<DocumentError>> parsed = ProfileFile.TryLoad(profilePath.FullName);
        if (!parsed.IsOk)
        {
            foreach (DocumentError issue in parsed.Error)
            {
                string pathSuffix = issue.Path is null ? "" : $" ({issue.Path})";
                CliLog.DocumentIssue(Log, issue.Code, issue.Message, pathSuffix);
            }

            exitCode = 1;
            return false;
        }

        Result<HostPlan, HostComposeError> planned = HostCompile.PlanDocument(parsed.Value, options);
        if (!planned.IsOk)
        {
            CliLog.Failure(Log, planned.Error.Code, planned.Error.Message);
            exitCode = 1;
            return false;
        }

        plan = planned.Value;
        exitCode = 0;
        return true;
    }

    private static void WritePlanHonesty(HostReview review)
    {
        CliLog.Lane(Log, review.ImageQuality);
        string honesty = review.Honesty;
        foreach (string line in honesty.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            if (line.StartsWith("Warning:", StringComparison.Ordinal))
            {
                CliLog.HonestyWarning(Log, line);
            }
            else if (line.Length > 0)
            {
                CliLog.HonestyLine(Log, line);
            }
        }
    }
}
