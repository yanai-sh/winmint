using WinMint.Orchestrator;

namespace WinMint.Tests;

internal static class ImageServicingTestFakes
{
    internal sealed class RecordingElevatedPlanRunner : IElevatedPlanRunner
    {
        public List<ServicingStage> Stages { get; } = [];
        public IEnumerable<ServicingOpcode> Opcodes => Stages.Select(s => s.Opcode);

        public Result<ImageEvidence, ServicingFailure> Execute(
            string workDirectory,
            IReadOnlyList<ServicingStage> stages,
            ServicingRun run,
            BuildArtifacts plan,
            CancellationToken ct)
        {
            Stages.AddRange(stages);
            ServicingStage? stamp = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.StampOfflineShell);
            if (stamp is null
                || !stamp.Parameters.TryGetValue(StageParams.ShellTarget, out string? shellTarget)
                || string.IsNullOrWhiteSpace(shellTarget))
            {
                return Result.Fail<ImageEvidence, ServicingFailure>(
                    new ServicingFailure(
                        "servicing.shellStamp.missing",
                        "StampOfflineShell stage missing or incomplete."));
            }

            return Result.Ok<ImageEvidence, ServicingFailure>(
                new ImageEvidence(
                    run.OutputIsoPath ?? Path.Combine(workDirectory, "out.iso"),
                    plan.Manifest.ImageQuality,
                    shellTarget,
                    new Dictionary<string, string>(StringComparer.Ordinal)));
        }
    }

    internal sealed class FailingElevatedPlanRunner : IElevatedPlanRunner
    {
        public Result<ImageEvidence, ServicingFailure> Execute(
            string workDirectory,
            IReadOnlyList<ServicingStage> stages,
            ServicingRun run,
            BuildArtifacts plan,
            CancellationToken ct)
        {
            Directory.CreateDirectory(Path.Combine(workDirectory, "logs"));
            File.WriteAllText(
                Path.Combine(workDirectory, "failure.json"),
                """{"schemaVersion":"winmint.image.evidence/v1","failed":true}""");
            return Result.Fail<ImageEvidence, ServicingFailure>(
                new ServicingFailure("servicing.stage.failed", "InjectUnattend failed (test)."));
        }
    }
}
