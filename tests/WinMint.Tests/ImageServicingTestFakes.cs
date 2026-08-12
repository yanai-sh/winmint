using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

internal static class ImageServicingTestFakes
{
    internal sealed class RecordingElevatedPlanRunner : IElevatedPlanRunner
    {
        public List<ServicingStage> Stages { get; } = [];
        public IEnumerable<ServicingOpcode> Opcodes => Stages.Select(s => s.Opcode);

        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            string workDirectory,
            IReadOnlyList<ServicingStage> stages,
            CancellationToken ct)
        {
            Stages.AddRange(stages);
            ServicingStage? stamp = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.StampOfflineShell);
            if (stamp is null
                || !stamp.Parameters.TryGetValue(StageParams.ShellTarget, out string? shellTarget)
                || string.IsNullOrWhiteSpace(shellTarget))
            {
                return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                    new Failure(
                        "servicing.shellStamp.missing",
                        "StampOfflineShell stage missing or incomplete.")));
            }

            ServicingStage? buildIso = stages.FirstOrDefault(s => s.Opcode == ServicingOpcode.BuildIso);
            if (buildIso is null
                || !buildIso.Parameters.TryGetValue(StageParams.OutputIso, out string? outputIso)
                || string.IsNullOrWhiteSpace(outputIso))
            {
                return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                    new Failure("servicing.outputIso.missing", "BuildIso stage missing outputIso.")));
            }

            // Minimal evidence fixture so ImageServicing.ReadEvidence can run (fake does not assemble ImageEvidence).
            string evidence = JsonSerializer.Serialize(
                new
                {
                    schemaVersion = ImageServicing.EvidenceSchemaVersion,
                    outputIsoPath = outputIso,
                    shellStampTargetPath = shellTarget,
                    digests = new Dictionary<string, string>(StringComparer.Ordinal)
                    {
                        ["outputIso.sha256"] = "test-digest",
                    },
                });
            File.WriteAllText(Path.Combine(workDirectory, "evidence.json"), evidence);
            return Task.FromResult(Result.Ok<ElevatedRunOk, Failure>(default));
        }
    }

    internal sealed class FailingElevatedPlanRunner : IElevatedPlanRunner
    {
        public Task<Result<ElevatedRunOk, Failure>> ExecuteAsync(
            string workDirectory,
            IReadOnlyList<ServicingStage> stages,
            CancellationToken ct)
        {
            _ = stages;
            Directory.CreateDirectory(Path.Combine(workDirectory, "logs"));
            File.WriteAllText(
                Path.Combine(workDirectory, "failure.json"),
                """{"schemaVersion":"winmint.image.evidence/v1","failed":true}""");
            return Task.FromResult(Result.Fail<ElevatedRunOk, Failure>(
                new Failure("servicing.stage.failed", "StageOobeUnattend failed (test).")));
        }
    }
}
