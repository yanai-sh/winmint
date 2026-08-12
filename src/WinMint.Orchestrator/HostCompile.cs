namespace WinMint.Orchestrator;

/// <summary>Orchestrator Profile → Plan → ImageServicing entry. Cli/Wizard stay thin adapters.</summary>
public static class HostCompile
{
    /// <summary>
    /// Profile/plan failures → <see cref="Result{TOk,TErr}.Error"/>.
    /// Plan success always yields <see cref="HostCompileResult.Plan"/>; Apply failure is
    /// <see cref="HostCompileResult.ApplyError"/> (so Cli can emit honesty without a second Plan).
    /// </summary>
    public static async Task<Result<HostCompileResult, Failure>> ApplyAsync(
        HostCompileRequest request,
        IElevatedPlanRunner? runner = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (string.IsNullOrWhiteSpace(request.ProfilePath) || !File.Exists(request.ProfilePath))
        {
            return Result.Fail<HostCompileResult, Failure>(
                new Failure(
                    "hostCompile.profile.missing",
                    $"Profile not found: {request.ProfilePath}"));
        }

        if (string.IsNullOrWhiteSpace(request.SourceIsoPath) || !File.Exists(request.SourceIsoPath))
        {
            return Result.Fail<HostCompileResult, Failure>(
                new Failure(
                    "hostCompile.sourceIso.missing",
                    $"Source ISO not found: {request.SourceIsoPath}"));
        }

        Result<Profile, IReadOnlyList<DocumentError>> parsed = ProfileFile.TryLoad(request.ProfilePath);
        if (!parsed.IsOk)
        {
            string detail = string.Join("; ", parsed.Error.Select(static i => $"{i.Code}: {i.Message}"));
            return Result.Fail<HostCompileResult, Failure>(
                new Failure("hostCompile.profile.invalid", detail));
        }

        // Before any DISM work: a stale publish yields an ISO that boots guest code you no longer have.
        // Only when a real elevated run follows — an injected runner produces no bootable media, so
        // holding those callers to the publish state would just make the suite hostage to it.
        if (runner is null && ImageServicing.CheckSupervisorFreshness() is { } staleSupervisor)
        {
            return Result.Fail<HostCompileResult, Failure>(staleSupervisor);
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
            return Result.Fail<HostCompileResult, Failure>(planned.Error);
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
        Result<ImageEvidence, Failure> applied =
            await ImageServicing.ApplyAsync(planned.Value, run, effective, cancellationToken)
                .ConfigureAwait(false);
        if (!applied.IsOk)
        {
            return Result.Ok<HostCompileResult, Failure>(
                new HostCompileResult(planned.Value, Evidence: null, applied.Error));
        }

        return Result.Ok<HostCompileResult, Failure>(
            new HostCompileResult(planned.Value, applied.Value, ApplyError: null));
    }
}

/// <summary>One Plan; Evidence set when Apply succeeds. ApplyError set when Plan ok but Apply failed.</summary>
public sealed record HostCompileResult(
    BuildArtifacts Plan,
    ImageEvidence? Evidence,
    Failure? ApplyError)
{
    public bool Succeeded => Evidence is not null && ApplyError is null;
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
