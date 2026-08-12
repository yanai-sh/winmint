namespace WinMint.Orchestrator;

/// <summary>Orchestrator Profile → Plan → ImageServicing entry. Cli/Wizard stay thin adapters.</summary>
public static class HostCompile
{
    public static async Task<Result<ImageEvidence, Failure>> ApplyAsync(
        HostCompileRequest request,
        IElevatedPlanRunner? runner = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (string.IsNullOrWhiteSpace(request.ProfilePath) || !File.Exists(request.ProfilePath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "hostCompile.profile.missing",
                    $"Profile not found: {request.ProfilePath}"));
        }

        if (string.IsNullOrWhiteSpace(request.SourceIsoPath) || !File.Exists(request.SourceIsoPath))
        {
            return Result.Fail<ImageEvidence, Failure>(
                new Failure(
                    "hostCompile.sourceIso.missing",
                    $"Source ISO not found: {request.SourceIsoPath}"));
        }

        Result<Profile, IReadOnlyList<DocumentError>> parsed = ProfileFile.TryLoad(request.ProfilePath);
        if (!parsed.IsOk)
        {
            string detail = string.Join("; ", parsed.Error.Select(static i => $"{i.Code}: {i.Message}"));
            return Result.Fail<ImageEvidence, Failure>(
                new Failure("hostCompile.profile.invalid", detail));
        }

        bool packageStrict = request.PackageStrict ?? HostDefaults.PackageStrictFor(request.ImageQuality);
        RunOptions runOptions = new()
        {
            ImageQuality = request.ImageQuality,
            SourceIsoPath = request.SourceIsoPath.Trim(),
            OutputIsoPath = string.IsNullOrWhiteSpace(request.OutputIsoPath) ? null : request.OutputIsoPath.Trim(),
            ImageArchitecture = request.ImageArchitecture,
            PackageAuditStrict = request.PackageAuditStrict,
            PackageStrict = packageStrict,
            IncludeSmokeStubs = request.IncludeSmokeStubs,
        };

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value, runOptions);
        if (!planned.IsOk)
        {
            return Result.Fail<ImageEvidence, Failure>(planned.Error);
        }

        string work = HostDefaults.ResolveWorkDirectory(request.ImageQuality, request.WorkDirectory);
        Directory.CreateDirectory(work);

        ServicingRun run = new(
            SourceIsoPath: request.SourceIsoPath.Trim(),
            WorkDirectory: work,
            OutputIsoPath: runOptions.OutputIsoPath,
            ProfilePath: request.ProfilePath.Trim(),
            WimIndex: request.WimIndex,
            ReuseMedia: request.ReuseMedia);

        IElevatedPlanRunner effective = runner ?? new PwshElevatedPlanRunner();
        return await ImageServicing.ApplyAsync(planned.Value, run, effective, cancellationToken)
            .ConfigureAwait(false);
    }
}

public sealed record HostCompileRequest(
    string ProfilePath,
    string SourceIsoPath,
    ImageQualityLane ImageQuality = ImageQualityLane.Test,
    string? WorkDirectory = null,
    string? OutputIsoPath = null,
    int? WimIndex = null,
    bool ReuseMedia = false,
    bool? PackageStrict = null,
    bool PackageAuditStrict = false,
    bool IncludeSmokeStubs = false,
    string? ImageArchitecture = null);
