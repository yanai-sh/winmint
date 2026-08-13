namespace WinMint.Orchestrator;

public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null,
    string? ProfilePath = null,
    int? WimIndex = null,
    string? SourceIsoSha256 = null,
    SelectedWim? SelectedImage = null);

public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests);

/// <summary>Elevation succeeded — evidence is ImageServicing's job.</summary>
public readonly record struct ElevatedRunOk;

/// <summary>
/// Elevated servicing-plan port — pwsh adapter + test fake (elevation only).
/// The stage list crosses this seam as <c>{workDirectory}/stages.json</c>, written by Materialize
/// and read by Invoke-ServicingPlan.ps1; adapters must not expect it in-process.
/// </summary>
public interface IElevatedPlanRunner
{
    Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
        string workDirectory,
        CancellationToken ct);
}
