namespace WinMint.Orchestrator;

public sealed record ServicingRun(
    string SourceIsoPath,
    string WorkDirectory,
    string? OutputIsoPath = null);

public sealed record ServicingFailure(string Code, string Message);

public sealed record ImageEvidence(
    string OutputIsoPath,
    ImageQualityLane Lane,
    string ShellStampTargetPath,
    IReadOnlyDictionary<string, string> Digests);

/// <summary>Elevated plan runner port — real pwsh adapter and test fake ship together (ticket 02).</summary>
public interface IElevatedPlanRunner
{
    Result<ImageEvidence, ServicingFailure> Execute(
        string workDirectory,
        IReadOnlyList<ServicingStage> stages,
        ServicingRun run,
        BuildArtifacts plan,
        CancellationToken ct);
}
