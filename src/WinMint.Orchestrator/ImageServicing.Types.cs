namespace WinMint.Orchestrator;

public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null,
    int? WimIndex = null,
    bool ReuseMedia = false);

public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests);

/// <summary>Elevated plan runner port — real pwsh adapter and test fake ship together (ticket 02).</summary>
public interface IElevatedPlanRunner
{
    Task<Result<ImageEvidence, Failure>> ExecuteAsync(
        string workDirectory,
        IReadOnlyList<ServicingStage> stages,
        ServicingRun run,
        BuildArtifacts plan,
        CancellationToken ct);
}
