namespace WinMint.Orchestrator;

public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null,
    string? ProfilePath = null,
    int? WimIndex = null,
    bool ReuseMedia = false);

public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests);

/// <summary>Elevation succeeded — evidence is ImageServicing's job.</summary>
public readonly record struct ElevatedRunOk;

/// <summary>Elevated RunPlan port — pwsh adapter + test fake (elevation only).</summary>
public interface IElevatedPlanRunner
{
    Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
        string workDirectory,
        IReadOnlyList<ServicingStage> stages,
        CancellationToken ct);
}
